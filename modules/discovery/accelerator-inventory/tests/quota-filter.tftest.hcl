# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
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
  compartment_id = "child-compartment"
  shape_names    = ["VM.GPU.Test.2"]
}


run "budget_is_used_only_for_shape_limits" {
  command = plan
  variables {
    shape_names      = []
    max_limit_checks = 1
  }
  assert {
    condition     = length(data.oci_limits_resource_availability.headroom) == 1 && alltrue([for query in data.oci_limits_resource_availability.headroom : query.limit_name == "gpu-test-count"])
    error_message = "Unrelated GPU limits must not consume the headroom request budget."
  }
}
run "filtered_zero_limit" {
  command = plan
  variables { only_shapes_with_limits = true }
  override_data {
    target = data.oci_limits_limit_values.compute
    values = { limit_values = [{ name = "gpu-test-count", scope_type = "AD", availability_domain = "AD-1", value = 0 }] }
  }
  assert {
    condition     = length(data.oci_limits_resource_availability.headroom) == 0 && tonumber(output.result.limits[0].tenancy_limit) == 0 && output.result.limits[0].resource_availability.reason == "Skipped by only_shapes_with_limits."
    error_message = "Filtered mode must retain zero limit metadata without spending headroom calls."
  }
}
run "filtered_ancillary_limits" {
  command = plan
  variables {
    only_shapes_with_limits = true
    shape_names             = []
  }
  assert {
    condition     = output.result.headroom_queries_used == 1
    error_message = "Filtered mode must only query shape-matched limits."
  }
}
