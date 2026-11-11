# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {}
variables {
  tenancy_ocid   = "root"
  compartment_id = "target"
  subnet_id      = "runner-subnet"
  name           = "fixture"
  config         = { name = "fixture", namespace = "fixture", model_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
}
override_data {
  target = data.oci_objectstorage_namespace.target
  values = { namespace = "fixture" }
}
override_data {
  target = data.oci_core_subnet.runner
  values = { compartment_id = "network-compartment" }
}
run "separate_benchmark_and_automatic_validation" {
  command = apply
  assert {
    condition     = length(oci_devops_deploy_pipeline.task) == 3 && oci_devops_deploy_stage.validate_after_deploy.deploy_stage_predecessor_collection[0].items[0].id == oci_devops_deploy_stage.task["deploy"].id && oci_devops_deploy_stage.task["benchmark"].deploy_pipeline_id != oci_devops_deploy_stage.task["deploy"].deploy_pipeline_id
    error_message = "Deploy must chain validation; benchmark must remain in its own explicitly invoked pipeline."
  }
  assert {
    condition     = oci_objectstorage_bucket.evidence.access_type == "NoPublicAccess" && length(output.delivery.bootstrap_rbac.items) == 9 && yamldecode(output.delivery.command_specs["benchmark"]).failImmediatelyOnError == true
    error_message = "Evidence storage must remain private and pipeline access/bootstrap must be explicit."
  }
}
