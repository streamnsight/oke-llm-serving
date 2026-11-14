# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {}
mock_provider "oci" { alias = "home" }
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
  # Existing service-managed prerequisites; tests never install an add-on.
  values = { addons = [
    { addon_name = "NvidiaDevicePlugin", current_installed_version = "fixture-device-plugin", version = "fixture-device-plugin", state = "ACTIVE", configurations = [] },
    { addon_name = "NvidiaNetworkOperator", current_installed_version = "fixture-network-operator", version = "fixture-network-operator", state = "ACTIVE", configurations = [] }
  ] }
}
run "regular_pool_and_cpu_capacity" {
  command = plan
  assert {
    condition     = length(oci_core_compute_cluster.gpu) == 0 && oci_containerengine_node_pool.gpu.node_config_details[0].size == 1 && oci_containerengine_node_pool.cpu[0].node_shape == "VM.Standard.E4.Flex"
    error_message = "Non-RDMA deployment must create a regular GPU pool and separate CPU capacity."
  }
  assert {
    condition     = oci_containerengine_node_pool.gpu.node_metadata["areLegacyImdsEndpointsDisabled"] == "true" && oci_containerengine_node_pool.cpu[0].node_metadata["areLegacyImdsEndpointsDisabled"] == "true"
    error_message = "Both GPU and optional CPU node launches must disable IMDSv1 so IMDSv2-only tenancies accept them."
  }
  assert {
    condition     = anytrue([for label in oci_containerengine_node_pool.gpu.initial_node_labels : label.key == "nvidia.com/gpu" && label.value == "true"])
    error_message = "GPU pools must advertise their hardware type with a node label before the device plugin becomes ready."
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
run "missing_native_gpu_addon_blocks_before_pool_allocation" {
  command = plan
  override_data {
    target = data.oci_containerengine_addons.target[0]
    values = { addons = [] }
  }
  expect_failures = [oci_containerengine_node_pool.gpu]
  assert {
    condition     = !output.addon_prerequisites.ready && output.addon_prerequisites.status == "blocked_native_addon_prerequisites" && strcontains(output.addon_prerequisites.blocking_reasons[0], "Enable or repair the OKE NVIDIA GPU Plugin")
    error_message = "An enhanced cluster with no native GPU device-plugin integration must fail before allocating a GPU pool, with an actionable service-managed remedy."
  }
}

run "inactive_gpu_addon_is_not_a_functioning_prerequisite" {
  command = plan
  override_data {
    target = data.oci_containerengine_addons.target[0]
    values = { addons = [{ addon_name = "NvidiaDevicePlugin", state = "NEEDS_ATTENTION", current_installed_version = "fixture", configurations = [] }] }
  }
  expect_failures = [oci_containerengine_node_pool.gpu]
  assert {
    condition     = output.addon_prerequisites.gpu.status == "missing_or_unusable_native_device_plugin"
    error_message = "A reported but unhealthy service add-on must not satisfy the native GPU prerequisite."
  }
}

run "gpu_operator_with_explicitly_disabled_device_plugin_is_insufficient" {
  command = plan
  override_data {
    target = data.oci_containerengine_addons.target[0]
    values = { addons = [{ addon_name = "NvidiaGpuOperator", state = "ACTIVE", current_installed_version = "fixture", configurations = [{ key = "devicePlugin.enabled", value = "false" }] }] }
  }
  expect_failures = [oci_containerengine_node_pool.gpu]
  assert {
    condition     = output.addon_prerequisites.gpu.observed_addons[0].device_plugin_explicitly_disabled
    error_message = "ACTIVE GPU Operator alone cannot supply device allocation when devicePlugin.enabled is explicitly false."
  }
}

run "gpu_operator_can_reuse_another_active_device_plugin" {
  command = plan
  override_data {
    target = data.oci_containerengine_addons.target[0]
    values = { addons = [
      { addon_name = "NvidiaGpuOperator", state = "ACTIVE", current_installed_version = "fixture", configurations = [{ key = "devicePlugin.enabled", value = "false" }, { key = "dcgmExporter.enabled", value = "true" }, { key = "dcgmExporter.serviceMonitor.enabled", value = "false" }] },
      { addon_name = "NvidiaDevicePlugin", state = "ACTIVE", current_installed_version = "fixture", configurations = [] }
    ] }
  }
  assert {
    condition     = output.addon_prerequisites.ready && output.addon_prerequisites.status == "native_addons_active_runtime_unverified" && output.addon_prerequisites.gpu_metrics.operator_configuration[0].exporter_enabled && !output.addon_prerequisites.gpu_metrics.operator_configuration[0].service_monitor_enabled && output.addon_prerequisites.gpu_metrics.status == "exporter_endpoint_and_prometheus_scraping_not_verified"
    error_message = "An independent active plugin is sufficient; exporter configuration must remain distinct from validated Prometheus scraping."
  }
}

run "null_device_plugin_setting_uses_the_documented_enabled_default" {
  command = plan
  override_data {
    target = data.oci_containerengine_addons.target[0]
    values = { addons = [{ addon_name = "NvidiaGpuOperator", state = "ACTIVE", current_installed_version = "fixture", configurations = [{ key = "devicePlugin.enabled", value = false ? "" : null }] }] }
  }
  assert {
    condition     = output.addon_prerequisites.ready && !output.addon_prerequisites.gpu.observed_addons[0].device_plugin_explicitly_disabled && output.allocation.addon_prerequisites.status == "native_addons_active_runtime_unverified"
    error_message = "An unset device-plugin configuration is different from explicitly disabling it."
  }
}

run "rdma_missing_network_operator_blocks_both_retained_resources" {
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
  override_data {
    target = data.oci_containerengine_addons.target[0]
    values = { addons = [{ addon_name = "NvidiaDevicePlugin", state = "ACTIVE", current_installed_version = "fixture", configurations = [] }] }
  }
  # Its failure also blocks the dependent node pool before pool evaluation.
  expect_failures = [oci_core_compute_cluster.gpu]
  assert {
    condition     = !output.addon_prerequisites.ready && output.addon_prerequisites.rdma.network_addon_status == "missing_or_inactive" && strcontains(output.addon_prerequisites.blocking_reasons[0], "managed pod-RDMA path") && strcontains(output.addon_prerequisites.rdma.host_agent_configuration, "Oracle Cloud Agent")
    error_message = "Absent native pod-network prerequisites must block both Compute Cluster and GPU allocation; automatic host RDMA agents do not prove Kubernetes device exposure."
  }
}

run "active_network_operator_does_not_prove_pod_rdma_or_gpudirect" {
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
    condition     = output.addon_prerequisites.ready && output.addon_prerequisites.rdma.network_addon_status == "active_configuration_unverified" && output.addon_prerequisites.rdma.pod_device_exposure == "unverified_until_gpu_nodes_advertise_selected_extended_rdma_resource" && output.addon_prerequisites.rdma.observed_addons[0].sriov_enabled == null && output.addon_prerequisites.management == "reuse_only_no_addon_creation_or_configuration_changes"
    error_message = "Service ACTIVE is prerequisite evidence only; missing SR-IOV configuration and actual pod-device/fabric operation remain unverified."
  }
}

run "basic_cluster_device_plugins_are_unknown_not_proven_absent" {
  command = plan
  override_data {
    target = data.oci_containerengine_cluster.target
    values = { state = "ACTIVE", type = "BASIC_CLUSTER", kubernetes_version = "v1.34.1" }
  }
  assert {
    condition     = output.addon_prerequisites.ready && output.addon_prerequisites.status == "unverified_basic_cluster" && output.addon_prerequisites.gpu.status == "not_assessed" && length(output.addon_prerequisites.gpu.observed_addons) == 0 && strcontains(output.addon_prerequisites.diagnostics[0], "availability is unknown")
    error_message = "Not querying enhanced-cluster add-ons on a basic cluster must not be presented as proof that a manually managed device plugin is missing or usable."
  }
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
run "gpu_only_pool_does_not_require_a_cpu_image_or_subnet" {
  command = plan
  variables {
    create_cpu_pool = false
    cpu_image_id    = null
    cpu_subnet_id   = null
  }
  assert {
    condition     = length(oci_containerengine_node_pool.cpu) == 0 && output.allocation.cpu_pool_id == null
    error_message = "A GPU-only allocation must not create a CPU node pool or require CPU image/network inputs."
  }
}
run "capture_retained_launch_bindings" {
  command = apply
  plan_options { target = [terraform_data.bindings] }
}
run "component_apply_cannot_follow_a_new_gpu_image" {
  command = plan
  variables { gpu_image_id = "new-discovered-image" }
  expect_failures = [oci_containerengine_node_pool.gpu]
}
run "unchanged_bindings_still_allow_normal_component_apply" {
  command = plan
  assert {
    condition     = terraform_data.bindings.output.image_id == var.gpu_image_id && oci_containerengine_node_pool.gpu.node_shape == var.gpu_shape
    error_message = "Frozen launch bindings must allow an unchanged allocation."
  }
}
run "component_apply_cannot_change_retained_boot_disk" {
  command = plan
  variables { boot_volume_gib = 300 }
  expect_failures = [oci_containerengine_node_pool.gpu]
}
