# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {}
variables {
  tenancy_ocid        = "root"
  compartment_id      = "target"
  cluster_id          = "cluster"
  region              = "region-one"
  availability_domain = "AD-1"
  subnet_id           = "gpu-subnet"
  cpu_subnet_id       = "cpu-subnet"
  gpu_image_id        = "gpu-image"
  cpu_image_id        = "cpu-image"
  gpu_shape           = "VM.GPU.A10.1"
  node_count          = 1
  name                = "fixture"
  requires_rdma       = false
  observation_id      = "fresh-test"
}
override_data {
  target = data.oci_containerengine_cluster.target
  values = { state = "ACTIVE", type = "ENHANCED_CLUSTER", kubernetes_version = "v1.34.1" }
}
override_data {
  target = data.oci_core_shapes.target
  values = { shapes = [{ name = "VM.GPU.A10.1", gpus = 1, rdma_ports = 0, quota_names = ["gpu-a10-count"] }] }
}
override_data {
  target = data.oci_containerengine_node_pool_option.target
  values = { shapes = ["VM.GPU.A10.1"] }
}
override_module {
  target  = module.capacity
  outputs = { result = { shapes = [{ reported_sufficient = true }] } }
}
override_data {
  target = data.oci_containerengine_addons.target[0]
  values = { addons = [] }
}
run "regular_pool_and_cpu_capacity" {
  command = plan
  assert {
    condition     = length(oci_core_compute_cluster.gpu) == 0 && oci_containerengine_node_pool.gpu.node_config_details[0].size == 1 && oci_containerengine_node_pool.cpu.node_shape == "VM.Standard.E4.Flex"
    error_message = "Non-RDMA deployment must create a regular GPU pool and separate CPU capacity."
  }
}
run "capacity_unknown_blocks_allocation" {
  command = plan
  override_module {
    target  = module.capacity
    outputs = { result = { shapes = [{ reported_sufficient = null }] } }
  }
  expect_failures = [oci_containerengine_node_pool.gpu]
}
run "rdma_requires_supported_shape" {
  command = plan
  variables { requires_rdma = true }
  expect_failures = [oci_containerengine_node_pool.gpu]
}
run "rdma_compute_cluster_pool" {
  command = plan
  variables {
    requires_rdma = true
    gpu_shape     = "BM.GPU4.8"
  }
  override_data {
    target = data.oci_containerengine_node_pool_option.target
    values = { shapes = ["BM.GPU4.8"] }
  }
  override_data {
    target = data.oci_core_shapes.target
    values = { shapes = [{ name = "BM.GPU4.8", gpus = 8, rdma_ports = 8, quota_names = ["gpu-a10-count"] }] }
  }
  assert {
    condition     = length(oci_core_compute_cluster.gpu) == 1 && length(oci_identity_policy.compute_cluster) == 1
    error_message = "RDMA pools must include native compute-cluster allocation and scoped launch policy."
  }
}
run "vcn_native_pod_network" {
  command = plan
  override_data {
    target = data.oci_containerengine_cluster.target
    values = { state = "ACTIVE", type = "ENHANCED_CLUSTER", kubernetes_version = "v1.34.1", cluster_pod_network_options = [{ cni_type = "OCI_VCN_IP_NATIVE" }] }
  }
  assert {
    condition     = oci_containerengine_node_pool.gpu.node_config_details[0].node_pool_pod_network_option_details[0].cni_type == "OCI_VCN_IP_NATIVE"
    error_message = "Managed GPU pools must inherit the cluster CNI mode."
  }
}
override_data {
  target = data.oci_containerengine_node_pools.owned
  values = { node_pools = [] }
}
override_module {
  target  = module.inventory
  outputs = { result = { limits = [{ name = "gpu-a10-count", description = "GPUs for test instances", scope_type = "AD", availability_domain = "AD-1", resource_availability = { available = 100, fractional_availability = null, status = "observed" } }] } }
}
# Seed only the built-in ownership resource, so retained-pool plan checks
# have a state identity without creating prevent_destroy-protected resources.
run "seed_allocation_identity" {
  command = apply
  plan_options { target = [terraform_data.identity] }
  override_resource {
    target = terraform_data.identity
    values = { id = "allocation-fixture" }
  }
}
run "retained_allocation_needs_no_spare_capacity" {
  command = plan
  override_resource {
    target = terraform_data.identity
    values = { id = "allocation-fixture" }
  }
  override_data {
    target = data.oci_containerengine_node_pools.owned
    values = { node_pools = [{ state = "ACTIVE", freeform_tags = { "oke-llm-allocation" = "allocation-fixture" }, node_config_details = [{ size = 1 }] }] }
  }
  override_module {
    target  = module.capacity
    outputs = { result = { shapes = [{ reported_sufficient = false }] } }
  }
  assert {
    condition     = output.allocation.retained_nodes == 1 && output.allocation.additional_nodes == 0
    error_message = "An already retained pool must not require replacement capacity."
  }
}
run "reject_releasing_retained_nodes" {
  command = plan
  override_resource {
    target = terraform_data.identity
    values = { id = "allocation-fixture" }
  }
  override_data {
    target = data.oci_containerengine_node_pools.owned
    values = { node_pools = [{ state = "ACTIVE", freeform_tags = { "oke-llm-allocation" = "allocation-fixture" }, node_config_details = [{ size = 2 }] }] }
  }
  expect_failures = [oci_containerengine_node_pool.gpu]
}
run "quantity_specific_entitlement_blocks_new_allocation" {
  command = plan
  override_module {
    target  = module.inventory
    outputs = { result = { limits = [{ name = "gpu-a10-count", description = "GPUs for test instances", scope_type = "AD", availability_domain = "AD-1", resource_availability = { available = 0, fractional_availability = null, status = "observed" } }] } }
  }
  expect_failures = [oci_containerengine_node_pool.gpu]
}

run "reports_service_addon_versions_without_installing_a_second_operator" {
  command = plan
  override_data {
    target = data.oci_containerengine_addons.target[0]
    values = { addons = [{ addon_name = "NvidiaGpuOperator", current_installed_version = "25.10.0", version = "25.10.0", state = "ACTIVE" }] }
  }
  assert {
    condition     = output.allocation.oke_addons[0].name == "NvidiaGpuOperator" && output.allocation.oke_addons[0].installed_version == "25.10.0" && output.allocation.oke_addons[0].state == "ACTIVE"
    error_message = "Use the service's installed add-on version as evidence, without a hardcoded self-managed operator release."
  }
}
