# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
  mock_data "oci_objectstorage_namespace" { defaults = { namespace = "fixture" } }
  mock_data "oci_core_subnet" { defaults = { compartment_id = "network-compartment" } }
}
mock_provider "oci" { alias = "home" }
run "direct_huggingface_needs_no_infrastructure_inputs" {
  command = plan
  assert {
    condition     = output.storage.mode == "direct_huggingface" && output.storage.pipeline_id == null && output.storage.bucket_name == null && output.bootstrap_manifest == null && length(oci_objectstorage_bucket.weights) == 0 && length(oci_devops_deploy_pipeline.stage) == 0 && length(oci_identity_policy.workload) == 0 && length(oci_generic_artifacts_content_artifact_by_path.input) == 0
    error_message = "Direct Hub serving must not create a bucket, staging pipeline, artifacts or IAM."
  }
}
run "object_storage_uses_retained_private_data_and_cpu_job_adapter" {
  command = plan
  variables {
    mode                   = "object_storage"
    name                   = "fixture"
    tenancy_ocid           = "tenancy"
    compartment_id         = "model-compartment"
    project_id             = "project"
    artifact_repository_id = "source-repository"
    cluster_id             = "cluster"
    cluster_compartment_id = "cluster-compartment"
    cluster_type           = "ENHANCED_CLUSTER"
    region                 = "eu-frankfurt-1"
    kubernetes_version     = "v1.34.1"
    subnet_id              = "runner-subnet"
    staging_image          = "registry.example/model-stager@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    cpu_node_selector      = { "node-pool" = "confirmed-cpu" }
    model = {
      id    = "owner/model", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", variant = "bf16"
      files = [{ path = "model.safetensors", size_bytes = 1048576, sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }, { path = "config.json", size_bytes = 256 }]
    }
  }
  assert {
    condition     = oci_objectstorage_bucket.weights[0].access_type == "NoPublicAccess" && oci_objectstorage_bucket.weights[0].versioning == "Enabled" && output.storage.retained && output.storage.runtime_status == "requires_validation" && endswith(output.storage.manifest_key, "/manifest.json")
    error_message = "Weights are retained private model data; Terraform must not claim a successful runtime transfer."
  }
  assert {
    condition     = length(oci_generic_artifacts_content_artifact_by_path.input) == 1 && jsondecode(oci_generic_artifacts_content_artifact_by_path.input["model.json"].content).model.revision == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" && oci_generic_artifacts_content_artifact_by_path.input["model.json"].version == sha256(local.config) && length(local.inline_files) == 4 && module.inline_command[0].byte_size <= 51200 && length(yamldecode(output.command_spec).inputArtifacts) == 1
    error_message = "Only the potentially large pinned manifest stays in Registry; four small source files and the complete command spec must be inline within the size limit."
  }
  assert {
    condition     = oci_devops_deploy_stage.stage[0].deploy_stage_type == "SHELL" && oci_devops_deploy_artifact.stage[0].argument_substitution_mode == "NONE" && oci_devops_deploy_artifact.stage[0].deploy_artifact_source[0].deploy_artifact_source_type == "INLINE" && strcontains(module.inline_command[0].preparation_command, "cat > 'stage.sh'") && keys(local.parameters) == ["JOB_DEADLINE_SECONDS", "STAGING_IMAGE"]
    error_message = "Use readable native variables and inline Shell sources; the runner only controls a CPU Job."
  }
  assert {
    condition     = !contains(keys(yamldecode(output.command_spec).env.variables), "RESULT_REPOSITORY_ID")
    error_message = "Routine staging reports belong in deployment logs and must not require a result repository."
  }
  assert {
    condition     = alltrue([for rule in oci_identity_policy.workload[0].statements : strcontains(rule, "request.principal.type = 'workload'") && strcontains(rule, "request.principal.namespace = 'fixture-staging'") && strcontains(rule, "request.principal.cluster_id = 'cluster'")]) && !strcontains(join("\n", oci_identity_policy.workload[0].statements), "OBJECT_DELETE")
    error_message = "Pod workload identity must be explicit and distinct from the runner, without model-delete permissions."
  }
  assert {
    condition     = output.bootstrap_manifest.items[1].automountServiceAccountToken && output.bootstrap_manifest.items[2].spec.resources.requests.storage == "64Gi" && output.bootstrap_manifest.items[4].roleRef.kind == "Role"
    error_message = "The bootstrap contract must bind service-account identity, retained scratch PVC and namespaced runner RBAC."
  }
}
run "mutable_revision_is_rejected" {
  command = plan
  variables {
    model = { id = "owner/model", revision = "main", variant = "bf16", files = [{ path = "config.json", size_bytes = 12 }] }
  }
  expect_failures = [var.model]
}
run "traversal_paths_are_rejected" {
  command = plan
  variables {
    model = { id = "owner/model", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", variant = "bf16", files = [{ path = "../escape", size_bytes = 12 }] }
  }
  expect_failures = [var.model]
}
run "unknown_file_sizes_are_rejected_without_null_arithmetic_errors" {
  command = plan
  variables {
    model = { id = "owner/model", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", variant = "bf16", files = [{ path = "model.safetensors", size_bytes = null }] }
  }
  expect_failures = [var.model]
}
run "staging_without_tested_image_fails_actionably" {
  command = plan
  variables {
    mode                   = "object_storage"
    tenancy_ocid           = "tenancy"
    compartment_id         = "model-compartment"
    project_id             = "project"
    artifact_repository_id = "repository"
    cluster_id             = "cluster"
    cluster_compartment_id = "cluster-compartment"
    cluster_type           = "ENHANCED_CLUSTER"
    region                 = "eu-frankfurt-1"
    kubernetes_version     = "v1.34.1"
    subnet_id              = "runner-subnet"
    cpu_node_selector      = { "node-pool" = "confirmed-cpu" }
    model                  = { id = "owner/model", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", variant = "bf16", files = [{ path = "config.json", size_bytes = 12 }] }
  }
  expect_failures = [terraform_data.requirements]
}
