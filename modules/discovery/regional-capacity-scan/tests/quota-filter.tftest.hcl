# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
  mock_data "oci_identity_region_subscriptions" {
    defaults = {
      region_subscriptions = [{ region_name = "region-one", status = "READY", is_home_region = true, region_key = "ONE" }]
    }
  }
  mock_data "oci_identity_availability_domains" {
    defaults = { availability_domains = [{ name = "AD-1" }] }
  }
  mock_data "oci_core_shapes" {
    defaults = {
      shapes = [
        { name = "VM.GPU.Test.2", gpus = 2, memory_in_gbs = 512, quota_names = ["gpu-test-count"] },
        { name = "VM.Standard.Test", gpus = 0, memory_in_gbs = 64, quota_names = [] }
      ]
    }
  }
  mock_data "oci_limits_limit_definitions" {
    defaults = {
      limit_definitions = [
        { name = "gpu-test-count", scope_type = "AD", is_resource_availability_supported = true },
        { name = "gpu-regional-count", scope_type = "REGION", is_resource_availability_supported = true },
        { name = "gpu-unsupported-count", scope_type = "REGION", is_resource_availability_supported = false }
      ]
    }
  }
  mock_data "oci_limits_limit_values" {
    defaults = {
      limit_values = [
        { name = "gpu-test-count", scope_type = "AD", availability_domain = "AD-1", value = 8 },
        { name = "gpu-regional-count", scope_type = "REGION", availability_domain = null, value = 16 },
        { name = "gpu-unsupported-count", scope_type = "REGION", availability_domain = null, value = 8 }
      ]
    }
  }
  mock_data "oci_limits_resource_availability" {
    defaults = { available = 6, used = 2, fractional_availability = 6, fractional_usage = 2, effective_quota_value = 8 }
  }
}

variables {
  tenancy_ocid   = "root-tenancy"
  region         = "region-one"
  observation_id = "quota-test"
}

run "broad_zero_limit" {
  command = plan
  override_data {
    target = module.inventory.data.oci_limits_limit_values.compute
    values = { limit_values = [{ name = "gpu-test-count", scope_type = "AD", availability_domain = "AD-1", value = 0 }] }
  }
  assert {
    condition     = length(module.capacity) == 1 && output.result.availability_domains[0].assessed_gpu_shapes == tolist(["VM.GPU.Test.2"])
    error_message = "Default broad mode must assess physical capacity despite a zero limit."
  }
}
run "filtered_zero_limit" {
  command = plan
  variables { only_shapes_with_limits = true }
  override_data {
    target = module.inventory.data.oci_limits_limit_values.compute
    values = { limit_values = [{ name = "gpu-test-count", scope_type = "AD", availability_domain = "AD-1", value = 0 }] }
  }
  assert {
    condition     = length(module.capacity) == 0 && output.result.availability_domains[0].status == "skipped_zero_limits" && output.result.availability_domains[0].skipped_zero_limit_shapes == tolist(["VM.GPU.Test.2"])
    error_message = "Confirmed zero limits must suppress capacity checks only in filtered mode."
  }
}
run "unknown_mapping_retained" {
  command = plan
  variables { only_shapes_with_limits = true }
  override_data {
    target = module.inventory.data.oci_limits_limit_values.compute
    values = { limit_values = [] }
  }
  assert {
    condition     = length(module.capacity) == 1 && length(output.inventory.availability_domains[0].shapes) == 1
    error_message = "Missing mappings must not be treated as zero limits."
  }
}
run "wrong_ad_zero_retained" {
  command = plan
  variables { only_shapes_with_limits = true }
  override_data {
    target = module.inventory.data.oci_limits_limit_values.compute
    values = { limit_values = [{ name = "gpu-test-count", scope_type = "AD", availability_domain = "AD-2", value = 0 }] }
  }
  assert {
    condition     = length(module.capacity) == 1
    error_message = "An unrelated AD zero limit must not suppress capacity."
  }
}
