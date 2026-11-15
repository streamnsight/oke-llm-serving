# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
  mock_resource "oci_artifacts_repository" { defaults = { id = "ocid1.artifactrepository.oc1.test.fixture" } }
  mock_data "oci_core_subnet" { defaults = { ipv6cidr_block = "", ipv6cidr_blocks = [] } }
  mock_data "oci_objectstorage_namespace" { defaults = { namespace = "fixture-namespace" } }
  mock_data "oci_identity_tenancy" { defaults = { home_region_key = "ORD" } }
  mock_data "oci_identity_regions" { defaults = { regions = [{ key = "ORD", name = "us-chicago-1" }] } }
}
mock_provider "oci" { alias = "home" }
variables {
  tenancy_ocid        = "root"
  compartment_ocid    = "stack-compartment"
  region              = "us-ashburn-1"
  cluster_id          = "cluster"
  availability_domain = "AD-1"
  gpu_shape           = "BM.GPU.A10.4"
  node_count          = 1
  platform_name       = "platform-fixture"
  skip_gpu_allocation = true
}
override_module {
  target = module.target
  outputs = { target = {
    ready        = true, issues = [], gpu_image = { id = "gpu-image" }, cpu_image = null, kubernetes_version = "v1.34.1",
    cluster_type = "ENHANCED_CLUSTER", cluster_compartment_id = "cluster-compartment", vcn_id = "vcn", subnet_id = "worker", cpu_subnet_id = "worker", devops_subnet_id = "runner", pod_subnet_id = null,
    gpu_nsg_ids  = [], cpu_nsg_ids = [], pod_nsg_ids = [], devops_nsg_ids = [], oke_addons = []
  } }
}
override_module {
  target  = module.native_addons
  outputs = { cluster_id = "addons-ready-cluster", status = { management = "enable_missing_reuse_existing_retain_on_destroy" } }
}
override_module {
  target  = module.allocation
  outputs = { allocation = { gpu_pool_id = "gpu-pool", cpu_pool_id = null, compute_cluster_id = null, allocation_identity = "allocation" } }
}
run "debug_creates_platform_without_gpu_allocation" {
  command = apply
  assert {
    condition     = length(module.allocation) == 0 && output.platform.project_id != null && output.platform.allocation.gpu_pool_id == null && output.platform.validation_scope == "cpu_components_only" && local.compartment_id == "stack-compartment" && output.infrastructure_preview.cpu_budget.creates_cpu_pool == false
    error_message = "Debug skipping must create the DevOps foundation while allocating no GPU or CPU pools."
  }
  assert {
    condition     = output.infrastructure_preview.gpu_count_per_host == 4 && output.infrastructure_preview.bootstrap.automatically_started == false && output.infrastructure_preview.cpu_placement == "existing_cluster_cpu_pools" && output.infrastructure_preview.iam_home_region == "us-chicago-1"
    error_message = "Describe actual host GPU count and explicit bootstrap on existing CPU capacity."
  }
}
run "provisioning_uses_platform_identity_and_never_asserts_ready" {
  command = apply
  variables { skip_gpu_allocation = false }
  assert {
    condition     = output.platform.platform_name == "platform-fixture" && output.platform.allocation.gpu_pool_id == "gpu-pool" && output.platform.cpu_placement == "existing_cluster_cpu_pools" && output.platform.runtime_readiness != "ready"
    error_message = "Publish stable pool/project references without claiming pipeline runtime validation."
  }
}
run "reject_unknown_gpu_shape" {
  command = plan
  variables { gpu_shape = "BM.GPU.Unknown.8" }
  expect_failures = [terraform_data.specification]
}
run "reject_rdma_on_a10" {
  command = plan
  variables { rdma_mode = "rdma" }
  expect_failures = [terraform_data.specification]
}
run "empty_rms_nsg_lists_preserve_discovered_policies" {
  command = plan
  variables {
    worker_nsg_ids = []
    pod_nsg_ids    = []
    devops_nsg_ids = []
  }
  assert {
    condition     = local.worker_nsg_ids == null && local.pod_nsg_ids == null && local.devops_nsg_ids == null
    error_message = "Empty RMS list controls must not silently remove inherited network security groups."
  }
}
run "single_host_h100_does_not_require_rdma" {
  command = plan
  variables { gpu_shape = "BM.GPU.H100.8" }
  assert {
    condition     = !output.infrastructure_preview.requires_rdma && output.infrastructure_preview.gpu_count_per_host == 8
    error_message = "A single-host model must not allocate an RDMA fabric based only on hardware capability."
  }
}
run "blank_rms_rows_preserve_inherited_nsgs" {
  command = plan
  variables {
    worker_nsg_ids = [""]
    pod_nsg_ids    = [" ", null]
    devops_nsg_ids = ["", "  "]
  }
  assert {
    condition     = local.worker_nsg_ids == null && local.pod_nsg_ids == null && local.devops_nsg_ids == null
    error_message = "RMS placeholder rows must not produce lookups for blank NSG IDs."
  }
}
run "actual_nsg_overrides_survive_blank_filtering" {
  command = plan
  variables {
    worker_nsg_ids = ["", " worker-nsg ", null, "worker-nsg"]
    pod_nsg_ids    = ["pod-nsg", " "]
    devops_nsg_ids = [" runner-nsg ", ""]
  }
  assert {
    condition     = local.worker_nsg_ids == tolist(["worker-nsg"]) && local.pod_nsg_ids == tolist(["pod-nsg"]) && local.devops_nsg_ids == tolist(["runner-nsg"])
    error_message = "Preserve, trim and deduplicate explicit NSG choices."
  }
}
run "auto_falls_back_to_ethernet_without_known_compute_cluster_support" {
  command = plan
  variables {
    gpu_shape = "BM.GPU.H100.8"
    region    = "new-region-1"
  }
  assert {
    condition     = !output.infrastructure_preview.requires_rdma
    error_message = "Unknown Compute Cluster availability must be explicit and default to a regular pool."
  }
}
run "explicit_rdma_in_an_unconfirmed_region_is_rejected" {
  command = plan
  variables {
    gpu_shape = "BM.GPU.H100.8"
    region    = "new-region-1"
    rdma_mode = "rdma"
  }
  expect_failures = [terraform_data.specification]
}
run "component_updates_use_artifact_registry_without_a_platform_bucket" {
  command = plan
  variables { node_count = 2 }
  assert {
    condition     = output.platform.specification.repository_id != null && output.platform.result_repository_id != null
    error_message = "Specifications and run reports belong in Generic Artifact Registry."
  }
}
