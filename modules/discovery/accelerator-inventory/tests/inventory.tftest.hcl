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
  compartment_id = "child-compartment"
  shape_names    = ["VM.GPU.Test.2"]
}

run "scopes_and_gpu_filter" {
  command = plan
  assert {
    condition     = data.oci_limits_limit_values.compute.compartment_id == "root-tenancy" && alltrue([for query in data.oci_limits_resource_availability.headroom : query.compartment_id == "child-compartment"])
    error_message = "Limit metadata must use root; headroom must use the target compartment."
  }
  assert {
    condition     = length(output.result.availability_domains[0].shapes) == 1 && output.result.availability_domains[0].shapes[0].gpu_memory_gib == null && output.result.availability_domains[0].shapes[0].host_memory_gb == 512
    error_message = "CPU shapes must be excluded and host RAM must not become GPU VRAM."
  }
  assert {
    condition     = output.result.status == "complete" && output.result.headroom_queries_used == 1 && alltrue([for query in data.oci_limits_resource_availability.headroom : query.availability_domain == "AD-1"])
    error_message = "AD-scoped headroom should query the exact AD once."
  }
}

run "regional_and_unsupported_limits" {
  command = plan
  variables { shape_names = [] }
  assert {
    condition     = output.result.status == "partial" && output.result.headroom_queries_used == 2
    error_message = "Unsupported limits should remain unknown without an API call."
  }
  assert {
    condition     = alltrue([for query in data.oci_limits_resource_availability.headroom : query.availability_domain == null if query.limit_name == "gpu-regional-count"])
    error_message = "Regional headroom must omit AD."
  }
}

run "budget_exhausted" {
  command = plan
  variables { max_limit_checks = 0 }
  assert {
    condition     = output.result.status == "partial" && length(data.oci_limits_resource_availability.headroom) == 0 && output.result.limits[0].resource_availability.available == null
    error_message = "A skipped query must not fabricate zero availability."
  }
}

run "explicit_exclusion" {
  command = plan
  variables { exclude_limit_names = ["gpu-test-count"] }
  assert {
    condition     = length(data.oci_limits_resource_availability.headroom) == 0 && output.result.limits[0].resource_availability.status == "unknown"
    error_message = "Explicitly excluded headroom must remain unknown."
  }
}

run "unmapped_quota_name" {
  command = plan
  override_data {
    target = data.oci_core_shapes.domain["AD-1"]
    values = {
      shapes = [{ name = "VM.GPU.Test.2", gpus = 2, quota_names = ["unknown-shape-quota"] }]
    }
  }
  assert {
    condition     = output.result.status == "partial" && contains(output.result.unmapped_shape_quota_names, "unknown-shape-quota") && output.result.headroom_queries_used == 0
    error_message = "Unknown quota-name mappings must not become guessed entitlement counts."
  }
}
