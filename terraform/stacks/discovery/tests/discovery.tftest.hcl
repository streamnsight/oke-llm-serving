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
  target = module.oci_discovery.data.external.scan
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
    condition = local.discovery_query.regions==jsonencode(["new-future-region-1"]) && local.discovery_query.shape_names==jsonencode(["BM.GPU.H100.8"])
    error_message = "Explicit region/shape subsets must reach the dynamic CLI lookup."
  }
}
run "direct_model_and_revision_are_forwarded" {
 command=plan
 variables {
  model="org/another-model"
  revision="requested-revision"
 }
 assert {
  condition=local.effective_model=="org/another-model" && local.effective_revision=="requested-revision"
  error_message="The direct model and revision must reach profiling without a catalog or saved choice."
 }
}
run "null_scopes_use_empty_defaults" {
  command = plan
  variables {
    regions = null
    shape_names = null
  }
  assert {
    condition = local.discovery_query.regions=="[]" && local.discovery_query.shape_names=="[]"
    error_message = "Null filters must become empty arrays rather than malformed external inputs."
  }
}

run "connection_region_is_optional_for_local_discovery" {
  command=plan
  variables { region=null }
  assert {
    condition=local.discovery_query.region==""
    error_message="Local discovery must use CLI defaults when no connection endpoint is supplied."
  }
}
run "deployment_inputs_is_one_directly_consumable_json_object" {
  command=plan
  assert {
    condition=output.deployment_inputs.discovery.schema_version=="2.0" && output.deployment_inputs.discovery.serving_configuration.status=="requires_expert_configuration" && can(output.deployment_inputs.discovery.assessment.candidates) && !can(output.deployment_inputs.discovery.regions)
    error_message="Emit one assessment/model/recipe object for deployment without requiring a script or repeating raw regional inventory."
  }
}
