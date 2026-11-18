# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "external" {}
mock_provider "http" {
  mock_data "http" { defaults = { status_code = 404, response_body = "{}" } }
}
mock_provider "oci" {
  mock_resource "oci_objectstorage_preauthrequest" {
    defaults = { full_path = "https://objectstorage.us-ashburn-1.oraclecloud.com/p/fake/n/fixture/b/artifacts/o/stack.zip" }
  }
}
variables {
  tenancy_ocid     = "root"
  compartment_ocid = "stack-compartment"
  region           = "us-ashburn-1"
  model            = "org/model"
}
override_module {
  target  = module.oci_discovery
  outputs = { result = { subscribed_regions = ["us-ashburn-1"], assessed_regions = ["us-ashburn-1"], regions = [], home_region = "us-ashburn-1" } }
}
override_module {
  target  = module.model_profile
  outputs = { profile = { model = { repository = "org/model", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, weights = { checkpoint_download_bytes = 1000 } } }
}
override_module {
  target  = module.serving_resolution
  outputs = { resolution = { engine = null } }
}
override_module {
  target = module.planner
  outputs = { assessment = {
    candidates = [], recommended_selection_id = "selected",
    suggestions = [for id in ["selected", "excluded"] : {
      id                   = id, region = "us-phoenix-1", availability_domain = "AD-1", gpu_shape = "BM.GPU.A10.4", node_count = 1,
      availability         = id == "selected" ? "available_at_scan" : "unconfirmed", configuration_origin = "suggested", runtime_validation = "not_run",
      tensor_parallel_size = 4, pipeline_parallel_size = 1, serving_configuration = { engine = { image = "fixture" } }, warnings = []
    }]
  } }
}
run "discovery_publishes_only_confirmed_choices" {
  command = apply
  assert {
    condition     = module.discovery_report.summary.option_count == 1 && toset(keys(module.discovery_report.summary.options)) == toset(["selected"]) && strcontains(local.published_options.selected.launch_url, "region=us-phoenix-1&zipUrl=") && strcontains(module.discovery_report.summary.options.selected.links.model_deployment.launch_url, "region=us-phoenix-1&zipUrl=") && module.infrastructure_publication[0].deployment_options.selected.artifact_region == "us-ashburn-1" && output.comparison_report_url != null
    error_message = "Publish confirmed choices only, retaining the distinction between storage region and deployment region."
  }
  assert {
    condition     = oci_objectstorage_object.comparison[0].content_type == "text/html; charset=utf-8" && oci_objectstorage_object.comparison[0].content_disposition == "inline" && oci_objectstorage_preauthrequest.comparison[0].access_type == "ObjectRead" && oci_objectstorage_preauthrequest.comparison[0].object_name == oci_objectstorage_object.comparison[0].object && oci_objectstorage_preauthrequest.comparison[0].time_expires == module.discovery_report.summary.options.selected.links.expires_at && strcontains(oci_objectstorage_object.comparison[0].content, trim(jsonencode(module.discovery_report.summary.options.selected.links.launch_url), "\""))
    error_message = "The separate HTML comparison page must use a scoped read PAR in the existing private publication bucket and expire with its bundle links."
  }
}
run "publication_can_be_disabled_for_discovery_only" {
  command = plan
  variables { publish_infrastructure_bundles = false }
  assert {
    condition     = length(module.infrastructure_publication) == 1 && module.discovery_report.summary.published_option_count == 0 && module.discovery_report.summary.option_count == 1 && module.discovery_report.summary.options.selected.links.launch_url == null && length(module.model_publication) == 0 && length(oci_objectstorage_object.comparison) == 1 && length(oci_objectstorage_preauthrequest.comparison) == 1
    error_message = "Assessment-only mode retains the HTML report and confirmed choices but publishes no infrastructure/model launch ZIPs."
  }
}

run "zero_options_still_publish_a_report" {
  command = apply
  override_module {
    target  = module.planner
    outputs = { assessment = { candidates = [], suggestions = [], blocking_reasons = ["No capacity confirmed"], recommended_selection_id = null } }
  }
  assert {
    condition     = output.comparison_report_url != null && module.discovery_report.summary.option_count == 0 && length(oci_objectstorage_object.comparison) == 1 && length(module.model_publication) == 0 && length(local.published_options) == 0 && strcontains(oci_objectstorage_object.comparison[0].content, "No capacity confirmed")
    error_message = "With no viable options the only output must still open a report explaining exclusions and regional evidence."
  }
}

run "routing_and_replica_requests_are_preserved_in_generated_model_inputs" {
  command = plan
  variables {
    replicas     = 2
    routing_mode = "kvaware"
  }
  assert {
    condition     = local.model_specifications.selected.model.requested_replicas == 2 && local.model_specifications.selected.model.routing_mode == "kvaware"
    error_message = "The configured model bundle must preserve the user's replica quantity and explicit routing policy separately from raw recipe evidence."
  }
}
