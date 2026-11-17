# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {}
variables {
  name           = "independent--model"
  compartment_id = "model-compartment"
  target         = { cluster_id = "existing-cluster", runner_subnet_id = "runner-subnet", runner_nsg_ids = [], metadata_ready = true, issues = [], allocation = { gpu_pool_id = null } }
}
run "owns_new_metadata_before_any_gpu_pool_exists" {
  command = apply
  assert {
    condition     = output.resources.project_id == oci_devops_project.model.id && startswith(oci_devops_project.model.name, "independent-model-") && oci_logging_log_group.model.display_name == oci_devops_project.model.name && oci_artifacts_repository.scripts.is_immutable && oci_artifacts_repository.results.is_immutable
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
run "names_are_stable_on_unchanged_reruns" {
  command = apply
  assert {
    condition     = output.resources.project_name == run.owns_new_metadata_before_any_gpu_pool_exists.resources.project_name && output.resources.instance_key == run.owns_new_metadata_before_any_gpu_pool_exists.resources.instance_key
    error_message = "A persisted per-stack identity must survive reruns without renaming its topic or project."
  }
}
run "model_punctuation_does_not_create_invalid_service_names" {
  command = plan
  assert {
    condition     = can(regex("^independent-model-[a-f0-9]{12}-notifications$", oci_ons_notification_topic.model.name)) && oci_devops_project.model.name == trimsuffix(oci_ons_notification_topic.model.name, "-notifications") && output.resources.instance_key == oci_ons_notification_topic.model.name
    error_message = "New topics and projects must use normalized, uniquely suffixed names and provide an independent namespace identity."
  }
}
