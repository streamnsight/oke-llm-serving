# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = { source = "oracle/oci", version = "~> 9.12", configuration_aliases = [oci.home] }
  }
}

data "oci_containerengine_cluster" "target" { cluster_id = var.cluster_id }
data "oci_containerengine_addons" "target" {
  count      = data.oci_containerengine_cluster.target.type == "ENHANCED_CLUSTER" ? 1 : 0
  cluster_id = coalesce(var.addon_cluster_id, var.cluster_id)
}
resource "terraform_data" "identity" { triggers_replace = var.name }
data "oci_containerengine_node_pools" "owned" {
  compartment_id = var.compartment_id
  cluster_id     = var.cluster_id
}
module "inventory" {
  source              = "../../discovery/accelerator-inventory"
  tenancy_ocid        = var.tenancy_ocid
  compartment_id      = var.compartment_id
  region              = var.region
  availability_domain = var.availability_domain
  shape_names         = [var.gpu_shape]
}
data "oci_core_shapes" "target" {
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain
  image_id            = var.gpu_image_id
}
data "oci_containerengine_node_pool_option" "target" {
  node_pool_option_id = var.cluster_id
  compartment_id      = var.compartment_id
}

locals {
  owned_pools          = [for pool in data.oci_containerengine_node_pools.owned.node_pools : pool if try(pool.freeform_tags["oke-llm-allocation"] == terraform_data.identity.id && pool.state == "ACTIVE", false)]
  retained_instances   = try(one(local.owned_pools).node_config_details[0].size, 0)
  additional_instances = max(0, var.node_count - local.retained_instances)
  shape                = try(one([for shape in data.oci_core_shapes.target.shapes : shape if shape.name == var.gpu_shape]), null)
  quota_checks = [for limit in module.inventory.result.limits : {
    name                     = limit.name
    description              = limit.description
    unit                     = try(startswith(limit.description, "GPUs for "), false) ? "GPUs" : "unknown"
    required_additional_gpus = try(local.shape.gpus * local.additional_instances, null)
    available                = try(coalesce(limit.resource_availability.fractional_availability, limit.resource_availability.available), null)
    sufficient               = try(startswith(limit.description, "GPUs for ") && limit.resource_availability.status == "observed" && coalesce(limit.resource_availability.fractional_availability, limit.resource_availability.available) >= local.shape.gpus * local.additional_instances, false)
  } if try(contains(local.shape.quota_names, limit.name), false) && (limit.scope_type != "AD" || limit.availability_domain == var.availability_domain)]
  quota_coverage_complete = try(length(local.shape.quota_names) > 0 && length(setsubtract(toset(local.shape.quota_names), toset([for check in local.quota_checks : check.name]))) == 0, false)
}

module "capacity" {
  source              = "../../discovery/capacity-assessment"
  tenancy_ocid        = var.tenancy_ocid
  region              = var.region
  availability_domain = var.availability_domain
  shape_names         = [var.gpu_shape]
  requested_instances = max(1, local.additional_instances)
  observation_id      = var.observation_id
}

resource "oci_core_compute_cluster" "gpu" {
  count               = var.requires_rdma ? 1 : 0
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain
  display_name        = var.name
  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = local.addon_prerequisites.ready
      error_message = join(" ", local.addon_prerequisites.blocking_reasons)
    }
  }
}
resource "oci_identity_policy" "compute_cluster" {
  provider       = oci.home
  count          = var.requires_rdma ? 1 : 0
  compartment_id = var.compartment_id
  name           = "${var.name}-compute-cluster"
  description    = "Permit managed OKE node pools to launch inside this compute cluster."
  statements     = ["allow any-user to {COMPUTE_CLUSTER_LAUNCH_INSTANCE} in compartment id ${var.compartment_id} where all {request.principal.type = 'nodepool', target.resource.id = '${oci_core_compute_cluster.gpu[0].id}'}"]
}

# Capture the launch bindings once. Later component-only Applies must fail
# before OKE can cycle retained GPUs to follow a newly discovered image/version.
resource "terraform_data" "bindings" {
  input = {
    cluster_id         = var.cluster_id, availability_domain = var.availability_domain,
    shape              = var.gpu_shape, image_id = var.gpu_image_id,
    kubernetes_version = data.oci_containerengine_cluster.target.kubernetes_version,
    subnet_id          = var.subnet_id, pod_subnet_id = var.pod_subnet_id,
    gpu_nsg_ids        = sort(var.gpu_nsg_ids), pod_nsg_ids = sort(var.pod_nsg_ids),
    boot_volume_gib    = var.boot_volume_gib, requires_rdma = var.requires_rdma
  }
  lifecycle { ignore_changes = [input] }
}

resource "oci_containerengine_node_pool" "gpu" {
  compartment_id     = var.compartment_id
  cluster_id         = var.cluster_id
  name               = var.name
  kubernetes_version = data.oci_containerengine_cluster.target.kubernetes_version
  node_shape         = var.gpu_shape
  node_metadata      = { areLegacyImdsEndpointsDisabled = "true" }
  freeform_tags      = { "oke-llm-allocation" = terraform_data.identity.id }
  node_source_details {
    source_type             = "IMAGE"
    image_id                = var.gpu_image_id
    boot_volume_size_in_gbs = tostring(var.boot_volume_gib)
  }
  initial_node_labels {
    key   = "oke-llm/allocation"
    value = var.name
  }
  initial_node_labels {
    key   = "nvidia.com/gpu"
    value = "true"
  }
  node_config_details {
    size               = var.node_count
    nsg_ids            = var.gpu_nsg_ids
    compute_cluster_id = var.requires_rdma ? oci_core_compute_cluster.gpu[0].id : null
    dynamic "node_pool_pod_network_option_details" {
      for_each = try(data.oci_containerengine_cluster.target.cluster_pod_network_options[0].cni_type == "OCI_VCN_IP_NATIVE", false) ? [1] : []
      content {
        cni_type          = "OCI_VCN_IP_NATIVE"
        pod_subnet_ids    = [coalesce(var.pod_subnet_id, var.subnet_id)]
        pod_nsg_ids       = var.pod_nsg_ids
        max_pods_per_node = 31
      }
    }
    placement_configs {
      availability_domain = var.availability_domain
      subnet_id           = var.subnet_id
    }
  }
  depends_on = [oci_identity_policy.compute_cluster]
  lifecycle {
    prevent_destroy      = true
    replace_triggered_by = [terraform_data.identity]
    precondition {
      condition     = local.addon_prerequisites.ready
      error_message = join(" ", local.addon_prerequisites.blocking_reasons)
    }
    precondition {
      condition = terraform_data.bindings.output == {
        cluster_id         = var.cluster_id, availability_domain = var.availability_domain,
        shape              = var.gpu_shape, image_id = var.gpu_image_id,
        kubernetes_version = data.oci_containerengine_cluster.target.kubernetes_version,
        subnet_id          = var.subnet_id, pod_subnet_id = var.pod_subnet_id,
        gpu_nsg_ids        = sort(var.gpu_nsg_ids), pod_nsg_ids = sort(var.pod_nsg_ids),
        boot_volume_gib    = var.boot_volume_gib, requires_rdma = var.requires_rdma
      }
      error_message = "Retained GPU launch bindings changed. Use an explicit pool maintenance procedure; component updates must not cycle GPUs or silently follow a newer image/Kubernetes version."
    }
    precondition {
      condition     = var.specification_id != "" && length(local.owned_pools) <= 1
      error_message = "The specification must pass validation and the state-owned allocation identity must be unique."
    }
    precondition {
      condition     = var.node_count >= local.retained_instances
      error_message = "This stack retains GPU allocations: reducing node_count releases scarce capacity and requires a separate explicit retirement procedure."
    }
    precondition {
      condition     = local.additional_instances == 0 || (local.quota_coverage_complete && alltrue([for check in local.quota_checks : check.sufficient]))
      error_message = "Quantity-specific GPU entitlement must cover additional instances. Unknown quota units/availability require assessment before allocation."
    }
    precondition {
      condition     = data.oci_containerengine_cluster.target.state == "ACTIVE" && (!var.requires_rdma || data.oci_containerengine_cluster.target.type == "ENHANCED_CLUSTER")
      error_message = "Cluster must be ACTIVE; RDMA managed pools require an enhanced cluster."
    }
    precondition {
      condition     = contains(data.oci_containerengine_node_pool_option.target.shapes, var.gpu_shape) && contains([for shape in data.oci_core_shapes.target.shapes : shape.name], var.gpu_shape)
      error_message = "Selected shape must be OKE-supported and visible with the selected image/AD/compartment."
    }
    precondition {
      condition     = !var.requires_rdma || (startswith(var.gpu_shape, "BM.") && anytrue([for shape in data.oci_core_shapes.target.shapes : try(shape.name == var.gpu_shape && shape.rdma_ports > 0, false)]))
      error_message = "RDMA allocation requires an explicitly RDMA-capable shape."
    }
    precondition {
      condition     = local.additional_instances == 0 || try(module.capacity.result.shapes[0].reported_sufficient == true, false)
      error_message = "A fresh capacity report must confirm the requested instance quantity before allocation. Unknown is not sufficient."
    }
  }
}

moved {
  from = oci_containerengine_node_pool.cpu
  to   = oci_containerengine_node_pool.cpu[0]
}
resource "oci_containerengine_node_pool" "cpu" {
  count              = var.create_cpu_pool ? 1 : 0
  depends_on         = [oci_containerengine_node_pool.gpu]
  compartment_id     = var.compartment_id
  cluster_id         = var.cluster_id
  name               = "${var.name}-control"
  kubernetes_version = data.oci_containerengine_cluster.target.kubernetes_version
  node_shape         = var.cpu_shape
  node_metadata      = { areLegacyImdsEndpointsDisabled = "true" }
  node_shape_config {
    ocpus         = var.cpu_ocpus
    memory_in_gbs = var.cpu_memory_gib
  }
  node_source_details {
    source_type = "IMAGE"
    image_id    = var.cpu_image_id
  }
  initial_node_labels {
    key   = "oke-llm/control"
    value = var.name
  }
  node_config_details {
    size    = var.cpu_node_count
    nsg_ids = var.cpu_nsg_ids
    dynamic "node_pool_pod_network_option_details" {
      for_each = try(data.oci_containerengine_cluster.target.cluster_pod_network_options[0].cni_type == "OCI_VCN_IP_NATIVE", false) ? [1] : []
      content {
        cni_type          = "OCI_VCN_IP_NATIVE"
        pod_subnet_ids    = [coalesce(var.pod_subnet_id, var.cpu_subnet_id)]
        pod_nsg_ids       = var.pod_nsg_ids
        max_pods_per_node = 31
      }
    }
    placement_configs {
      availability_domain = var.availability_domain
      subnet_id           = var.cpu_subnet_id
    }
  }
  lifecycle { prevent_destroy = true }
}
output "allocation" {
  value = { addon_prerequisites = local.addon_prerequisites, oke_addons = try([for addon in data.oci_containerengine_addons.target[0].addons : { name = addon.addon_name, installed_version = addon.current_installed_version, requested_version = addon.version, state = addon.state }], []), gpu_pool_id = oci_containerengine_node_pool.gpu.id, cpu_pool_id = try(oci_containerengine_node_pool.cpu[0].id, null), compute_cluster_id = try(oci_core_compute_cluster.gpu[0].id, null), kubernetes_version = data.oci_containerengine_cluster.target.kubernetes_version, name = var.name, allocation_identity = terraform_data.identity.id, requested_nodes = var.node_count, retained_nodes = local.retained_instances, additional_nodes = local.additional_instances, quota_checks = local.quota_checks, cluster_compartment_id = data.oci_containerengine_cluster.target.compartment_id, capacity = module.capacity.result }
}
