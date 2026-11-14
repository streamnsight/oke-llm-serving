# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "external" {}
mock_provider "http" {
  mock_data "http" { defaults = { status_code = 404, response_body = "{}" } }
}
mock_provider "oci" {}
mock_provider "archive" {}
variables {
  tenancy_ocid = "test-root"
  region       = "us-chicago-1"
  model        = "org/model"
}
override_data {
  target = module.oci_discovery.data.external.scan
  values = { result = { result = "{\"subscribed_regions\": [\"us-chicago-1\", \"new-future-region-1\"], \"assessed_regions\": [\"us-chicago-1\", \"new-future-region-1\"], \"regions\": []}" } }
}
override_module {
  target  = module.model_profile
  outputs = { profile = { memory = { status = "unsupported" } } }
}
override_module {
  target  = module.planner
  outputs = { assessment = { candidates = [], status = "requires_validation" } }
}
override_module {
  target  = module.serving_resolution
  outputs = { resolution = { engine = null, engine_issues = ["fixture"], status = "requires_expert_configuration" } }
}
run "all_ready_subscriptions_include_new_regions" {
  command = plan
  assert {
    condition     = length(var.regions) == 0 && length(var.shape_names) == 0 && contains(module.discovery_report.summary.scan.assessed_regions, "new-future-region-1")
    error_message = "Empty scope must accept CLI-discovered regions without provider aliases."
  }
}
run "explicit_scope_is_forwarded_to_cli" {
  command = plan
  variables {
    regions     = ["new-future-region-1"]
    shape_names = ["BM.GPU.H100.8"]
  }
  assert {
    condition     = local.discovery_query.regions == jsonencode(["new-future-region-1"]) && local.discovery_query.shape_names == jsonencode(["BM.GPU.H100.8"])
    error_message = "Explicit region/shape subsets must reach the dynamic CLI lookup."
  }
}
run "direct_model_and_revision_are_forwarded" {
  command = plan
  variables {
    model    = "org/another-model"
    revision = "requested-revision"
  }
  assert {
    condition     = local.effective_model == "org/another-model" && local.effective_revision == "requested-revision"
    error_message = "The direct model and revision must reach profiling without a catalog or saved choice."
  }
}
run "null_scopes_use_empty_defaults" {
  command = plan
  variables {
    regions     = null
    shape_names = null
  }
  assert {
    condition     = local.discovery_query.regions == "[]" && local.discovery_query.shape_names == "[]"
    error_message = "Null filters must become empty arrays rather than malformed external inputs."
  }
}

run "connection_region_is_optional_for_local_discovery" {
  command = plan
  variables { region = null }
  assert {
    condition     = local.discovery_query.region == ""
    error_message = "Local discovery must use CLI defaults when no connection endpoint is supplied."
  }
}
run "normal_discovery_is_embedded_in_the_report" {
  command = plan
  assert {
    condition     = module.discovery_report.summary.schema_version == "4.0" && module.discovery_report.summary.diagnostics == null && !contains(keys(module.discovery_report.summary), "profile") && !contains(keys(module.discovery_report.summary), "assessment") && module.discovery_report.summary.option_count == 0 && length(module.discovery_report.summary.failure_summary) > 0 && !var.include_diagnostics
    error_message = "The HTML embeds a useful report without exposing duplicate root JSON outputs."
  }
}
run "full_diagnostics_are_opt_in" {
  command = plan
  variables { include_diagnostics = true }
  assert {
    condition     = module.discovery_report.summary.diagnostics.serving_configuration.status == "requires_expert_configuration" && module.discovery_report.summary.diagnostics.profile.memory.status == "unsupported"
    error_message = "Retain full audit evidence behind one explicit diagnostic option."
  }
}
