# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "external" {}
mock_provider "http" {}
variables {
  tenancy_ocid = "test-root"
  region = "us-chicago-1"
  model = "org/model"
}
override_data {
  target = data.external.oci_discovery
  values = {result={result="{\"subscribed_regions\": [\"us-chicago-1\", \"new-future-region-1\"], \"assessed_regions\": [\"us-chicago-1\", \"new-future-region-1\"], \"regions\": []}"}}
}
override_module {
  target = module.model_profile
  outputs = {profile={memory={status="unsupported"}}}
}
override_module {
  target = module.planner
  outputs = {assessment={candidates=[],status="requires_validation"}}
}
override_module {
  target = module.serving_resolution
  outputs = {resolution={engine=null,engine_issues=["fixture"],status="requires_expert_configuration"}}
}
run "all_ready_subscriptions_include_new_regions" {
  command = plan
  assert {
    condition = length(var.regions)==0 && length(var.shape_names)==0 && contains(output.discovery.assessed_regions,"new-future-region-1")
    error_message = "Empty scope must accept CLI-discovered regions without provider aliases."
  }
}
run "explicit_scope_is_forwarded_to_cli" {
  command = plan
  variables {
    regions = ["new-future-region-1"]
    shape_names = ["BM.GPU.H100.8"]
  }
  assert {
    condition = data.external.oci_discovery.query.regions==jsonencode(["new-future-region-1"]) && data.external.oci_discovery.query.shape_names==jsonencode(["BM.GPU.H100.8"])
    error_message = "Explicit region/shape subsets must reach the dynamic CLI lookup."
  }
}
run "legacy_recipe_choice_resolves_model_revision" {
  command = plan
  variables {
    model_choice = "RecursiveSI/flint"
    model = null
  }
  assert {
    condition = local.effective_model=="RecursiveSI/flint" && local.effective_revision=="main"
    error_message = "A legacy recipe choice remains supported without using recipe commits as model commits."
  }
}
run "explicit_model_takes_priority_over_saved_choice" {
  command = plan
  variables {
    model_choice = "RecursiveSI/flint"
    model = "org/another-model"
    revision = "requested-revision"
  }
  assert {
    condition = local.effective_model=="org/another-model" && local.effective_revision=="requested-revision"
    error_message = "The visible URL input must not be ignored because an old RMS stack saved a catalog choice."
  }
}
run "null_scopes_use_empty_defaults" {
  command = plan
  variables {
    regions = null
    shape_names = null
  }
  assert {
    condition = data.external.oci_discovery.query.regions=="[]" && data.external.oci_discovery.query.shape_names=="[]"
    error_message = "Null filters must become empty arrays rather than malformed external inputs."
  }
}

run "connection_region_is_optional_for_local_discovery" {
  command=plan
  variables { region=null }
  assert {
    condition=data.external.oci_discovery.query.region==""
    error_message="Local discovery must use CLI defaults when no connection endpoint is supplied."
  }
}
