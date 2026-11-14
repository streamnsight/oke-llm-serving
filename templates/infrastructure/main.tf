# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12" } }
}
provider "oci" { region = var.region }
data "oci_identity_tenancy" "target" { tenancy_id = var.tenancy_ocid }
data "oci_identity_regions" "available" {}
provider "oci" {
  alias  = "home"
  region = local.home_region
}
locals {
  home_region    = one([for region in data.oci_identity_regions.available.regions : region.name if region.key == data.oci_identity_tenancy.target.home_region_key])
  compartment_id = coalesce(var.compartment_id, var.compartment_ocid, var.tenancy_ocid)
  catalog        = jsondecode(file("${path.module}/../../modules/discovery/accelerator-inventory/data/gpus.json"))
  gpu            = try(local.catalog.shapes[var.gpu_shape], null)
  requires_rdma  = var.rdma_mode == "auto" ? try(local.selected_specification.selection.platform_plan.topology.rdma_required, local.selected_specification.selection.requires_rdma, false) : var.rdma_mode == "rdma"
  nsg_overrides = {
    for key, values in { worker = var.worker_nsg_ids, pod = var.pod_nsg_ids, devops = var.devops_nsg_ids } : key => distinct([
      for value in coalesce(values, []) : trimspace(value) if try(trimspace(value) != "", false)
    ])
  }
  worker_nsg_ids         = length(local.nsg_overrides.worker) > 0 ? local.nsg_overrides.worker : null
  pod_nsg_ids            = length(local.nsg_overrides.pod) > 0 ? local.nsg_overrides.pod : null
  devops_nsg_ids         = length(local.nsg_overrides.devops) > 0 ? local.nsg_overrides.devops : null
  cpu_shape              = "VM.Standard.E4.Flex"
  selected_specification = fileexists("${path.module}/inputs/infrastructure-spec.json") ? jsondecode(file("${path.module}/inputs/infrastructure-spec.json")) : null
  recommendation_changes = local.selected_specification == null ? [] : [for key, value in local.selected_specification.recommendation : key if try({
    availability_domain = var.availability_domain, gpu_shape = var.gpu_shape, node_count = var.node_count,
    boot_volume_gib     = var.boot_volume_gib, skip_gpu_allocation = var.skip_gpu_allocation,
    enable_lws          = var.enable_lws, enable_disaggregated_set = var.enable_disaggregated_set, monitoring_enabled = var.monitoring_enabled, autoscaling_enabled = var.autoscaling_enabled, rdma_mode = var.rdma_mode, model_storage_mode = var.model_storage_mode
  }[key] != value, false) && key != "skip_gpu_allocation"]
  specification = {
    schema_version              = "1.0", platform_name = var.platform_name, region = var.region, cluster_id = var.cluster_id,
    availability_domain         = var.availability_domain, gpu_shape = var.gpu_shape, gpu_count_per_host = try(local.gpu.gpus, 0), node_count = var.node_count,
    gpu_memory_bytes_per_device = try(local.gpu.memory_bytes_per_gpu, null),
    requires_rdma               = local.requires_rdma, rdma_resource_name = var.rdma_resource_name, enable_lws = var.enable_lws,
    monitoring_enabled          = var.monitoring_enabled, autoscaling_enabled = var.autoscaling_enabled,
    cluster_authorization_mode  = var.cluster_authorization_mode,
    enable_disaggregated_set    = var.enable_disaggregated_set, component_modes = { lws = var.lws_mode, prometheus = var.prometheus_mode, keda = var.keda_mode },
    cpu_placement               = "existing_cluster_cpu_pools", gpu_allocation_enabled = !var.skip_gpu_allocation,
    boot_volume_gib             = var.boot_volume_gib, target = module.target.target
  }
}
module "target" {
  source              = "../../modules/infrastructure/deployment-target"
  cluster_id          = var.cluster_id
  availability_domain = var.availability_domain
  gpu_shape           = var.gpu_shape
  gpu_architecture    = try(local.gpu.cpu_architecture, "amd64")
  cpu_shape           = local.cpu_shape
  resolve_cpu_image   = false
  os_version          = var.os_version
  requires_rdma       = local.requires_rdma
  worker_nsg_ids      = local.worker_nsg_ids
  pod_nsg_ids         = local.pod_nsg_ids
  devops_nsg_ids      = local.devops_nsg_ids
  overrides           = { for k, v in { gpu_image_id = var.gpu_image_id, cpu_image_id = null, subnet_id = var.subnet_id, cpu_subnet_id = null, devops_subnet_id = var.devops_subnet_id, pod_subnet_id = var.pod_subnet_id } : k => try(trimspace(v) != "" ? trimspace(v) : null, null) }
}
resource "terraform_data" "specification" {
  input = local.specification
  lifecycle {
    precondition {
      condition     = local.selected_specification == null ? true : var.region == local.selected_specification.region
      error_message = "This ZIP targets another region. Open its generated RMS launch URL in the recommended region."
    }
    precondition {
      condition     = try(local.gpu.compute_capability != null && local.gpu.gpus > 0, false)
      error_message = "This first platform bootstrap supports cataloged NVIDIA GPU shapes only."
    }
    precondition {
      condition     = module.target.target.ready
      error_message = "Target lookup failed: ${join("; ", module.target.target.issues)}"
    }
    precondition {
      condition     = !local.requires_rdma || try(local.gpu.compute_cluster_supported && contains(local.catalog.compute_cluster_regions, var.region), false)
      error_message = "RDMA requires a cataloged Compute Cluster shape and supported region. Select Ethernet explicitly if appropriate."
    }
  }
}
module "allocation" {
  providers           = { oci = oci, oci.home = oci.home }
  count               = var.skip_gpu_allocation ? 0 : 1
  source              = "../../modules/infrastructure/gpu-allocation"
  tenancy_ocid        = var.tenancy_ocid
  compartment_id      = local.compartment_id
  cluster_id          = var.cluster_id
  region              = var.region
  availability_domain = var.availability_domain
  name                = var.platform_name
  gpu_shape           = var.gpu_shape
  node_count          = var.node_count
  requires_rdma       = local.requires_rdma
  observation_id      = coalesce(var.observation_id, plantimestamp())
  gpu_image_id        = module.target.target.gpu_image.id
  create_cpu_pool     = false
  subnet_id           = module.target.target.subnet_id
  pod_subnet_id       = module.target.target.pod_subnet_id
  gpu_nsg_ids         = module.target.target.gpu_nsg_ids
  pod_nsg_ids         = module.target.target.pod_nsg_ids
  boot_volume_gib     = var.boot_volume_gib
  specification_id    = terraform_data.specification.id
}
module "bootstrap" {
  providers      = { oci = oci, oci.home = oci.home }
  source         = "../../modules/cluster-add-ons/platform-bootstrap"
  tenancy_ocid   = var.tenancy_ocid
  compartment_id = local.compartment_id
  name           = var.platform_name
  subnet_id      = module.target.target.devops_subnet_id
  nsg_ids        = module.target.target.devops_nsg_ids
  config = merge(local.specification, {
    allocation = { for k in ["gpu_pool_id", "compute_cluster_id", "allocation_identity"] : k => var.skip_gpu_allocation ? null : module.allocation[0].allocation[k] }
  })
}
output "infrastructure_preview" {
  value = merge(local.specification, {
    iam_home_region         = local.home_region,
    skip_gpu_allocation     = var.skip_gpu_allocation,
    selected_recommendation = local.selected_specification == null ? null : { selection_id = local.selected_specification.selection_id, changed_fields = local.recommendation_changes, status = length(local.recommendation_changes) == 0 ? "original_recommendation; model runtime validation pending" : "expert_modified; original model sizing not validated for these changes" },
    network_selection       = local.requires_rdma ? "RDMA Compute Cluster placement; fabric validation pending" : "Ethernet pool; no inter-host RDMA fabric selected by this execution plan",
    gpu_selector            = "oke-llm/allocation=${var.platform_name}",
    cpu_budget              = module.bootstrap.platform.cpu_budget,
    bootstrap               = { type = "OCI DevOps native Helm + Shell", automatically_started = false, gpu_network_support = "reuse OKE-managed capabilities; verify actual allocatable resources", shared_controllers = module.bootstrap.platform.required_components, model_workloads = "none" },
    runtime_readiness       = "not_checked_by_terraform", gpu_kernel_cuda_rdma_validation = "requires_live_nodes_and_later_model_tests"
  })
}
output "allocation" { value = try(module.allocation[0].allocation, null) }
output "platform" { value = module.bootstrap.platform }
output "bootstrap_rbac" { value = module.bootstrap.bootstrap_rbac }
