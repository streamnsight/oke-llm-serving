mock_provider "external" {}

run "runtime_free_profile" {
  command = plan
  variables {
    profile_json = jsonencode({ schema_version = "1.0", model = { resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, memory = { status = "unsupported" } })
  }
  assert {
    condition     = length(data.external.model) == 0 && output.profile.memory.status == "unsupported"
    error_message = "Precomputed profiles must not launch any Python program or invent a numeric estimate."
  }
}

run "no_implicit_python" {
  command         = plan
  expect_failures = [output.profile]
}

run "reject_wrong_schema" {
  command = plan
  variables {
    profile_json = jsonencode({ schema_version = "2.0", model = { resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } })
  }
  expect_failures = [var.profile_json]
}

run "external_analysis_requires_opt_in" {
  command = plan
  variables {
    enable_external_analysis = true
    model                    = "org/model"
  }
  override_data {
    target = data.external.model[0]
    values = {
      result = { profile_json = "{\"schema_version\":\"1.0\",\"memory\":{\"status\":\"estimated\"}}" }
    }
  }
  assert {
    condition     = length(data.external.model) == 1 && output.profile.memory.status == "estimated"
    error_message = "Prepared runners may explicitly opt into external model inspection."
  }
}
