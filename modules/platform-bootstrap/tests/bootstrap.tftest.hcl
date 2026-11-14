# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {}
mock_provider "oci" { alias = "home" }
variables {
  tenancy_ocid   = "root"
  compartment_id = "platform-compartment"
  name           = "fixture"
  subnet_id      = "runner"
  config = {
    platform_name = "fixture", region = "us-ashburn-1", cluster_id = "cluster", gpu_shape = "BM.GPU.A10.4", node_count = 1, gpu_count_per_host = 4,
    cpu_placement = "existing_cluster_cpu_pools", target = { cluster_compartment_id = "cluster-compartment", kubernetes_version = "v1.34.1" },
    allocation    = { gpu_pool_id = "gpu-pool", compute_cluster_id = null, allocation_identity = "pool-identity" }
  }
}
run "platform_has_explicit_shell_bootstrap_and_separate_readiness" {
  command = apply
  assert {
    condition     = oci_devops_deploy_stage.bootstrap.deploy_stage_type == "SHELL" && oci_devops_deploy_stage.validate.deploy_stage_type == "SHELL" && oci_devops_deploy_artifact.bootstrap.argument_substitution_mode == "NONE" && yamldecode(local.command_specs.deploy).env.variables.LWS_VERSION == "$${LWS_VERSION}" && !strcontains(local.command_specs.deploy, "base64")
    error_message = "Use native environment variables and separate component/validation pipelines without encoded payloads."
  }
  assert {
    condition     = output.bootstrap_rbac.subjects[0].name == output.platform.bootstrap_pipeline_id && output.bootstrap_rbac.subjects[1].name == output.platform.validation_pipeline_id && output.bootstrap_rbac.roleRef.name == "cluster-admin" && output.platform.component_pipeline_ids.lws == output.platform.bootstrap_pipeline_id
    error_message = "Both explicit pipeline principals must be declared for cluster authorization."
  }
  assert {
    condition     = jsondecode(oci_objectstorage_object.specification.content).generation == output.platform.generation && oci_objectstorage_object.specification.object == "fixture/platform-spec.json" && endswith(output.platform.readiness_uri, "${output.platform.generation}/readiness.json") && output.platform.cpu_placement == "existing_cluster_cpu_pools"
    error_message = "Terraform owns desired specification; pipeline readiness must have a separate generation-specific object."
  }
  assert {
    condition     = oci_objectstorage_bucket.platform.access_type == "NoPublicAccess" && !contains(keys(output.platform.allocation), "cpu_pool_id")
    error_message = "The platform descriptor must stay private and refer only to GPU infrastructure."
  }
  assert {
    condition     = anytrue([for rule in oci_identity_policy.bootstrap.statements : strcontains(rule, "to manage compute-containers in compartment id platform-compartment")]) && anytrue([for rule in oci_identity_policy.bootstrap.statements : strcontains(rule, "to manage compute-container-instances in compartment id platform-compartment")])
    error_message = "A DevOps Shell stage requires both container-instance and container permissions."
  }
  assert {
    condition     = oci_artifacts_repository.scripts.is_immutable && length(oci_generic_artifacts_content_artifact_by_path.script) == 4 && alltrue([for script, artifact in oci_generic_artifacts_content_artifact_by_path.script : artifact.content == file("${path.module}/scripts/${script}") && artifact.version == filesha256("${path.module}/scripts/${script}")]) && alltrue([for spec in values(local.command_specs) : length(yamldecode(spec).inputArtifacts) == 4 && strcontains(yamldecode(spec).steps[0].command, "sha256sum -c -") && !strcontains(yamldecode(spec).steps[0].command, "os object get") && strcontains(yamldecode(spec).steps[0].command, "export ") && !strcontains(yamldecode(spec).steps[0].command, "$${LWS_VERSION}")])
    error_message = "Versioned script artifacts must be input files, checksum verified, with explicit exports for child processes."
  }
  assert {
    condition     = { for item in oci_devops_deploy_pipeline.bootstrap.deploy_pipeline_parameters[0].items : item.name => item.default_value } == local.parameters && !contains(keys(local.parameters), "GPU_SHAPES") && yamldecode(local.command_specs.validate).env.variables.PLATFORM_MODE == "validate" && strcontains(oci_identity_dynamic_group.bootstrap.matching_rule, oci_devops_deploy_pipeline.validate.id)
    error_message = "Run parameters must populate environment defaults and both identities must have scoped OCI access."
  }
  assert {
    condition     = alltrue(flatten([for spec in values(local.command_specs) : [for key in keys(yamldecode(spec).env.variables) : contains(split(" ", split("\n", yamldecode(spec).steps[0].command)[1]), key)]]))
    error_message = "Every native Shell variable must be explicitly exported before starting Bash/jq child processes."
  }
}
