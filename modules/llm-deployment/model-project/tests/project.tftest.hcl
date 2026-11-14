# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {}
variables {
  name           = "independent-model"
  compartment_id = "model-compartment"
  target = { cluster_id = "existing-cluster", runner_subnet_id = "runner-subnet", runner_nsg_ids = [], metadata_ready = true, issues = [], allocation = { gpu_pool_id = null } }
}
run "owns_new_metadata_before_any_gpu_pool_exists" {
  command = apply
  assert {
    condition     = output.resources.project_id == oci_devops_project.model.id && oci_devops_project.model.name == "independent-model" && oci_artifacts_repository.scripts.is_immutable && oci_artifacts_repository.results.is_immutable
    error_message = "Each model stack owns its own project and immutable software/results repositories."
  }
  assert {
    condition     = oci_devops_deploy_environment.model.cluster_id == "existing-cluster" && oci_devops_deploy_environment.model.project_id == oci_devops_project.model.id && oci_devops_deploy_environment.model.network_channel[0].network_channel_type == "PRIVATE_ENDPOINT_CHANNEL" && oci_devops_deploy_environment.model.network_channel[0].subnet_id == "runner-subnet"
    error_message = "The native Helm environment belongs to the model project and reuses the selected existing cluster/network."
  }
}
run "network_ambiguity_blocks_metadata_creation" {
  command = plan
  variables { target = { cluster_id = "existing-cluster", runner_subnet_id = "runner-subnet", runner_nsg_ids = [], metadata_ready = false, issues = ["ambiguous runner subnet"] } }
  expect_failures = [oci_devops_project.model]
}
run "model_punctuation_does_not_create_an_invalid_notification_topic" {
  command = plan
  variables { name = "m-qwen-qwen3-8--cd680c-71f707f4" }
  assert {
    condition     = oci_ons_notification_topic.model.name == "m-qwen-qwen3-8-cd680c-71f707f4-notifications"
    error_message = "Generated model names must collapse consecutive dashes for OCI Notifications while preserving project identity."
  }
}
