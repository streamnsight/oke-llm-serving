# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Run this state-sharing upgrade regression with Terraform 1.14+ and
# -test-directory=tests/upgrades; the default suite remains compatible with 1.9.8.
mock_provider "oci" {}
run "legacy_stack" {
  command   = apply
  state_key = "migration"
  module { source = "./tests/fixtures/legacy" }
}
run "legacy_topic_preserves_project_and_namespace_identity" {
  command   = plan
  state_key = "migration"
  variables {
    name           = "legacy-model"
    compartment_id = "compartment"
    target         = { cluster_id = "cluster", runner_subnet_id = "subnet", runner_nsg_ids = [], metadata_ready = true, issues = [] }
  }
  assert {
    condition     = output.resources.project_name == run.legacy_stack.project_name && output.resources.instance_key == null && oci_ons_notification_topic.model.name == run.legacy_stack.topic_name
    error_message = "An existing unsuffixed topic must retain its project name and original default namespace."
  }
}
