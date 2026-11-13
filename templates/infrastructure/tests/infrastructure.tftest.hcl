# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {}
variables {
  tenancy_ocid        = "root"
  compartment_ocid    = "stack-compartment"
  region              = "us-ashburn-1"
  cluster_id          = "cluster"
  availability_domain = "AD-1"
  gpu_shape           = "BM.GPU.A10.4"
  node_count          = 1
  platform_name       = "platform-fixture"
}
override_module {
  target = module.target
  outputs = { target = {
    ready                  = true, issues = [], gpu_image = { id = "gpu-image" }, cpu_image = null, kubernetes_version = "v1.34.1",
    cluster_compartment_id = "cluster-compartment", vcn_id = "vcn", subnet_id = "worker", cpu_subnet_id = "worker", devops_subnet_id = "runner", pod_subnet_id = null,
    gpu_nsg_ids            = [], cpu_nsg_ids = [], pod_nsg_ids = [], devops_nsg_ids = [], oke_addons = []
  } }
}
override_module {
  target  = module.allocation
  outputs = { allocation = { gpu_pool_id = "gpu-pool", cpu_pool_id = null, compute_cluster_id = null, allocation_identity = "allocation" } }
}
run "preview_has_no_allocation_bootstrap_or_model_dependency" {
  command = plan
  assert {
    condition     = length(module.allocation) == 0 && length(module.bootstrap) == 0 && local.compartment_id == "stack-compartment" && output.infrastructure_preview.cpu_budget.creates_cpu_pool == false
    error_message = "Default preview must not instantiate OCI resource modules or require a CPU image/model configuration."
  }
  assert {
    condition     = output.infrastructure_preview.gpu_count_per_host == 4 && output.infrastructure_preview.bootstrap.automatically_started == false && output.infrastructure_preview.cpu_placement == "existing_cluster_cpu_pools"
    error_message = "Describe actual host GPU count and explicit bootstrap on existing CPU capacity."
  }
}
run "provisioning_uses_platform_identity_and_never_asserts_ready" {
  command = apply
  variables { provision_resources = true }
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
run "h100_defaults_to_rdma" {
  command = plan
  variables { gpu_shape = "BM.GPU.H100.8" }
  assert {
    condition     = output.infrastructure_preview.requires_rdma && output.infrastructure_preview.gpu_count_per_host == 8
    error_message = "RDMA-capable shapes should default to their supported topology."
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
    condition     = !output.infrastructure_preview.requires_rdma && strcontains(output.infrastructure_preview.network_selection, "Ethernet fallback")
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
