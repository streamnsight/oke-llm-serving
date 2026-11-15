# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
  mock_data "oci_containerengine_addon_options" {
    defaults = { addon_options = [
      { name = "NodeFeatureDiscovery", state = "ACTIVE", versions = [{ status = "ACTIVE", version_number = "fixture" }] },
      { name = "NvidiaGpuOperator", state = "ACTIVE", versions = [{ status = "ACTIVE", version_number = "fixture" }] },
      { name = "GpuHealthMonitoring", state = "ACTIVE", versions = [{ status = "ACTIVE", version_number = "fixture" }] }
    ] }
  }
  mock_data "oci_containerengine_addons" { defaults = { addons = [] } }
}
variables {
  cluster_id         = "ocid1.cluster.oc1.test.fixture"
  cluster_type       = "ENHANCED_CLUSTER"
  kubernetes_version = "v1.34.1"
  region             = "eu-frankfurt-1"
  gpu_shape          = "BM.GPU.A10.4"
  requires_rdma      = false
  installed_addons   = []
}
run "ensure_on_cpu_debug_path_and_retain_shared_services" {
  command = apply
  assert {
    condition     = output.cluster_id == "ocid1.cluster.oc1.test.fixture" && output.status.management == "enable_missing_reuse_existing_retain_on_destroy" && output.status.health_addon_requested && !output.status.rdma_required
    error_message = "Missing OKE dependencies must be ensured independently of GPU allocation, with shared retention."
  }
}
run "unchanged_inventory_does_not_replace_the_ensure_step" {
  command = plan
  assert {
    condition     = terraform_data.ensure.output.cluster_id == "ocid1.cluster.oc1.test.fixture"
    error_message = "Stable inventory and requirements must preserve the applied ensure step without a timestamp replacement."
  }
}
run "do_not_enable_bare_metal_health_on_vm" {
  command = plan
  variables { gpu_shape = "VM.GPU.A10.1" }
  assert {
    condition     = !output.status.health_addon_requested
    error_message = "VM selections must not request the bare-metal health controller."
  }
}
run "skip_unavailable_optional_health_controller" {
  command = plan
  override_data {
    target = data.oci_containerengine_addon_options.compatible
    values = { addon_options = [{ name = "GpuHealthMonitoring", state = "ACTIVE", versions = [{ status = "DEPRECATED", version_number = "old" }] }] }
  }
  assert {
    condition     = !output.status.health_addon_requested
    error_message = "Deprecated or unavailable health options must not be installed."
  }
}
run "reject_basic_cluster_before_enablement" {
  command = plan
  variables { cluster_type = "BASIC_CLUSTER" }
  expect_failures = [terraform_data.ensure]
}
