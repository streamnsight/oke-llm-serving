# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12" } }
}
provider "oci" { region = var.region }
locals {
  compartment_id = coalesce(var.compartment_id, var.compartment_ocid, var.tenancy_ocid)
  catalog        = jsondecode(file("${path.module}/../../modules/accelerator-inventory/data/gpus.json"))
  gpu            = try(local.catalog.shapes[var.gpu_shape], null)
  requires_rdma  = var.rdma_mode == "auto" ? try(local.gpu.rdma && local.gpu.compute_cluster_supported && contains(local.catalog.compute_cluster_regions, var.region), false) : var.rdma_mode == "rdma"
  worker_nsg_ids = try(length(var.worker_nsg_ids) > 0, false) ? var.worker_nsg_ids : null
  pod_nsg_ids    = try(length(var.pod_nsg_ids) > 0, false) ? var.pod_nsg_ids : null
  devops_nsg_ids = try(length(var.devops_nsg_ids) > 0, false) ? var.devops_nsg_ids : null
  cpu_shape      = "VM.Standard.E4.Flex"
  specification = {
    schema_version              = "1.0", platform_name = var.platform_name, region = var.region, cluster_id = var.cluster_id,
    availability_domain         = var.availability_domain, gpu_shape = var.gpu_shape, gpu_count_per_host = try(local.gpu.gpus, 0), node_count = var.node_count,
    gpu_memory_bytes_per_device = try(local.gpu.memory_bytes_per_gpu, null),
    requires_rdma               = local.requires_rdma, rdma_resource_name = var.rdma_resource_name, enable_lws = var.enable_lws,
    cpu_placement               = "existing_cluster_cpu_pools", gpu_shapes = keys(local.catalog.shapes),
    boot_volume_gib             = var.boot_volume_gib, target = module.target.target
  }
}
module "target" {
  source              = "../../modules/deployment-target"
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
      condition     = try(local.gpu.compute_capability != null && local.gpu.gpus > 0, false)
      error_message = "This first platform bootstrap supports cataloged NVIDIA GPU shapes only."
    }
    precondition {
      condition     = module.target.target.ready
      error_message = "Resolve the image/network issues shown by the target lookup before proceeding."
    }
    precondition {
      condition     = !local.requires_rdma || try(local.gpu.compute_cluster_supported && contains(local.catalog.compute_cluster_regions, var.region), false)
      error_message = "RDMA requires a cataloged Compute Cluster shape and supported region. Select Ethernet explicitly if appropriate."
    }
  }
}
module "allocation" {
  count               = var.provision_resources ? 1 : 0
  source              = "../../modules/gpu-allocation"
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
  count          = var.provision_resources ? 1 : 0
  source         = "../../modules/platform-bootstrap"
  tenancy_ocid   = var.tenancy_ocid
  compartment_id = local.compartment_id
  name           = var.platform_name
  subnet_id      = module.target.target.devops_subnet_id
  nsg_ids        = module.target.target.devops_nsg_ids
  config = merge(local.specification, {
    allocation = { for k in ["gpu_pool_id", "compute_cluster_id", "allocation_identity"] : k => module.allocation[0].allocation[k] }
  })
}
output "infrastructure_preview" {
  value = merge(local.specification, {
    provision_resources = var.provision_resources,
    network_selection   = var.rdma_mode == "auto" && try(local.gpu.rdma, false) && !local.requires_rdma ? "Ethernet fallback: Compute Cluster placement is not cataloged for this shape/region; no RDMA transport is claimed." : local.requires_rdma ? "RDMA Compute Cluster placement; fabric validation pending" : "Ethernet managed GPU pool",
    gpu_selector        = "oke-llm/allocation=${var.platform_name}",
    cpu_budget          = { placement = "existing_cluster_cpu_pools", creates_cpu_pool = false, lws_requests = { cpu = "1", memory = "1Gi" }, capacity = "check existing CPU nodes; actual scheduling validated by controller rollout" },
    bootstrap           = { type = "OCI DevOps SHELL", automatically_started = false, gpu_network_support = "reuse OKE-managed capabilities; verify actual allocatable resources", shared_controller = var.enable_lws ? "LeaderWorkerSet" : "none", model_workloads = "none" },
    runtime_readiness   = "not_checked_by_terraform", gpu_kernel_cuda_rdma_validation = "requires_live_nodes_and_later_model_tests"
  })
}
output "allocation" { value = try(module.allocation[0].allocation, null) }
output "platform" { value = try(module.bootstrap[0].platform, null) }
output "bootstrap_rbac" { value = try(module.bootstrap[0].bootstrap_rbac, null) }
