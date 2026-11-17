# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {}
run "independent_stacks_with_identical_model_inputs_have_distinct_names" {
  command = apply
  module { source = "./tests/fixtures/instances" }
  assert {
    condition     = output.first.project_name != output.second.project_name && try(output.first.instance_key != output.second.instance_key && output.first.log_group_name != output.second.log_group_name, false)
    error_message = "Separate stack states for the same model must not collide on project/topic identity or default namespace seed."
  }
}
