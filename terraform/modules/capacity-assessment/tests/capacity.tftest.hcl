mock_provider "oci" {
  mock_resource "oci_core_compute_capacity_report" {
    defaults = {
      time_created = "2026-11-11T00:00:00Z"
    }
  }
}

variables {
  tenancy_ocid        = "root-tenancy"
  region              = "region-one"
  availability_domain = "AD-1"
  shape_names         = ["VM.GPU.Test.2"]
  observation_id      = "test-run-1"
  requested_instances = 3
}

run "insufficient_instances" {
  command = apply
  override_resource {
    target = oci_core_compute_capacity_report.report
    values = {
      time_created         = "2026-11-11T00:00:00Z"
      shape_availabilities = { availability_status = "AVAILABLE", available_count = "2" }
    }
  }
  assert {
    condition     = oci_core_compute_capacity_report.report.compartment_id == "root-tenancy" && output.result.shapes[0].reported_sufficient == false && output.result.shapes[0].available_instances == 2
    error_message = "Reports must use root and compare instances without multiplying by GPU count."
  }
}

run "unsupported_is_unknown" {
  command = apply
  variables { observation_id = "unsupported-run" }
  override_resource {
    target = oci_core_compute_capacity_report.report
    values = {
      shape_availabilities = { availability_status = "HARDWARE_NOT_SUPPORTED", available_count = "0" }
    }
  }
  assert {
    condition     = output.result.status == "partial" && output.result.shapes[0].reported_sufficient == null
    error_message = "Unsupported observation is not proof of zero hardware capacity."
  }
}

run "known_zero_capacity" {
  command = apply
  variables { observation_id = "zero-capacity-run" }
  override_resource {
    target = oci_core_compute_capacity_report.report
    values = {
      shape_availabilities = { availability_status = "OUT_OF_HOST_CAPACITY", available_count = "0" }
    }
  }
  assert {
    condition     = output.result.status == "complete" && output.result.shapes[0].reported_sufficient == false && output.result.shapes[0].available_instances == 0
    error_message = "Out-of-capacity is a known negative observation."
  }
}

run "invalid_count_is_unknown" {
  command = apply
  variables { observation_id = "invalid-count-run" }
  override_resource {
    target = oci_core_compute_capacity_report.report
    values = {
      shape_availabilities = { availability_status = "AVAILABLE", available_count = "not-a-count" }
    }
  }
  assert {
    condition     = output.result.status == "partial" && output.result.shapes[0].available_instances == null && output.result.shapes[0].reported_sufficient == null
    error_message = "Non-numeric counts must not imply available hardware."
  }
}

run "explicit_refresh_id" {
  command = apply
  variables { observation_id = "test-run-2" }
  assert {
    condition     = terraform_data.observation.triggers_replace == "test-run-2" && output.result.observation_id == "test-run-2"
    error_message = "A refreshed observation must record the new run ID."
  }
}
