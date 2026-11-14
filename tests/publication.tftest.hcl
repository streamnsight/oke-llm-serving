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
    condition     = output.deployment_option_count == 1 && toset(keys(output.discovery.options)) == toset(["selected"]) && strcontains(output.recommended_launch_url, "region=us-phoenix-1&zipUrl=") && module.infrastructure_publication[0].deployment_options.selected.artifact_region == "us-ashburn-1" && output.comparison_report_url != null
    error_message = "Publish confirmed choices only, retaining the distinction between storage region and deployment region."
  }
  assert {
    condition     = oci_objectstorage_object.comparison[0].content_type == "text/html; charset=utf-8" && oci_objectstorage_object.comparison[0].content_disposition == "inline" && oci_objectstorage_preauthrequest.comparison[0].access_type == "ObjectRead" && oci_objectstorage_preauthrequest.comparison[0].object_name == oci_objectstorage_object.comparison[0].object && oci_objectstorage_preauthrequest.comparison[0].time_expires == output.discovery.options.selected.links.expires_at && strcontains(oci_objectstorage_object.comparison[0].content, trim(jsonencode(output.discovery.options.selected.links.launch_url), "\""))
    error_message = "The separate HTML comparison page must use a scoped read PAR in the existing private publication bucket and expire with its bundle links."
  }
}
run "publication_can_be_disabled_for_discovery_only" {
  command = plan
  variables { publish_infrastructure_bundles = false }
  assert {
    condition     = length(module.infrastructure_publication) == 0 && output.discovery.published_option_count == 0 && output.deployment_option_count == 1 && output.discovery.options.selected.links.launch_url == null && output.recommended_launch_url == null && output.comparison_report_url == null && length(oci_objectstorage_object.comparison) == 0
    error_message = "Discovery-only mode retains confirmed choices but creates no publisher/report resources or launch links."
  }
}
run "debug_gpu_gate_reaches_the_publisher" {
  command = apply
  variables { skip_gpu_allocation = true }
  assert {
    condition     = output.discovery.options.selected.skip_gpu_allocation
    error_message = "Discovery's debug setting must reach the actual published option."
  }
}
