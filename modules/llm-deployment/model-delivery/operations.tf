# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  operation_shared_files = {
    "operation.sh"       = file("${path.module}/scripts/operation.sh")
    "lock.sh"            = file("${path.module}/../../shared/component-delivery/scripts/lock.sh")
    "tools.sh"           = file("${path.module}/../../shared/component-delivery/scripts/tools.sh")
    "specification.json" = jsonencode({ cluster_id = var.platform.cluster_id, helm_version = "v3.19.2" })
  }
  operation_files = { for operation in ["validate", "benchmark"] : operation => merge(local.operation_shared_files, {
    for asset in(operation == "validate" ? ["validate.sh"] : ["benchmark.sh", "bench-client.sh"]) : asset => file("${path.module}/scripts/${asset}")
  }) }
  # These inputs already exist for model deployment; reuse their immutable
  # paths/versions instead of duplicating the large common library inline.
  operation_input_files = { for path in ["common.sh", "config.json"] : path => local.runtime_files[path] }
  operation_parameters = merge(local.defaults, {
    CHART_VERSION     = local.chart_version, RECOVER_LOCK_HOLDER = "none",
    BENCHMARK_BACKEND = var.benchmark_backend, BENCHMARK_REQUESTS = "64", BENCHMARK_INPUT_TOKENS = "256", BENCHMARK_OUTPUT_TOKENS = "64"
  })
  operation_specs = { for operation in ["validate", "benchmark"] : operation => yamlencode({
    version = "0.1", component = "command", shell = "bash", timeoutInSeconds = 3600, failImmediatelyOnError = true,
    env = { variables = merge({ for key in keys(local.operation_parameters) : key => "$${${key}}" }, {
      DELIVERY_OPERATION     = operation, DELIVERY_GENERATION = module.delivery.generations.workload,
      DELIVERY_REGION        = var.platform.region,
      DELIVERY_DEPLOYMENT_ID = "$${OCI_DEPLOYMENT_ID}", DELIVERY_PIPELINE_ID = "$${OCI_PIPELINE_ID}",
      OCI_CLI_AUTH           = "resource_principal", OCI_CLI_REGION = var.platform.region
    }, operation == "benchmark" ? { DELIVERY_RESULT_REPOSITORY = var.platform.result_repository_id } : {}) },
    inputArtifacts = [for path in sort(keys(local.operation_input_files)) : {
      name       = "model-${replace(path, ".", "-")}", type = "GENERIC_ARTIFACT", location = "./runtime/${path}",
      registryId = var.platform.script_repository_id, path = module.delivery.runtime_artifacts[path].artifact_path, version = module.delivery.runtime_artifacts[path].version
    }],
    steps = [{ type = "Command", name = "${operation}-current-model", timeoutInSeconds = 3600, command = join("\n", concat([
      "set -euo pipefail",
      "export ${join(" ", sort(concat(keys(local.operation_parameters), ["DELIVERY_OPERATION", "DELIVERY_GENERATION", "DELIVERY_REGION", "DELIVERY_DEPLOYMENT_ID", "DELIVERY_PIPELINE_ID", "OCI_DEPLOYMENT_ID", "OCI_PIPELINE_ID", "OCI_CLI_AUTH", "OCI_CLI_REGION"], operation == "benchmark" ? ["DELIVERY_RESULT_REPOSITORY"] : [])))}"
      ], [for path, content in merge(local.operation_files[operation], local.operation_input_files) : "printf '%s  runtime/${path}\\n' '${sha256(content)}' | sha256sum -c -"], [
      "cp runtime/specification.json specification.json", "bash runtime/operation.sh"
    ])) }]
  }) }
  all_pipeline_ids = concat(module.delivery.all_pipeline_ids, [for op in sort(keys(oci_devops_deploy_pipeline.operation)) : oci_devops_deploy_pipeline.operation[op].id])
}
module "inline_operation" {
  for_each      = local.operation_specs
  source        = "../../shared/inline-command-spec"
  specification = yamldecode(each.value)
  files         = { for path, content in local.operation_files[each.key] : "runtime/${path}" => content }
}
resource "oci_devops_deploy_artifact" "operation" {
  for_each                   = local.operation_specs
  project_id                 = var.platform.project_id
  display_name               = "${local.identity}-${each.key}-command"
  deploy_artifact_type       = "COMMAND_SPEC"
  argument_substitution_mode = "NONE"
  deploy_artifact_source {
    deploy_artifact_source_type = "INLINE"
    base64encoded_content       = base64encode(module.inline_operation[each.key].content)
  }
}
resource "oci_devops_deploy_pipeline" "operation" {
  for_each     = toset(["validate", "benchmark"])
  project_id   = var.platform.project_id
  display_name = "${local.identity}-${each.key}"
  description  = "Explicit ${each.key} operation; uses the same model lease and current validated Helm generation. Never starts on Terraform apply."
  deploy_pipeline_parameters {
    dynamic "items" {
      for_each = local.operation_parameters
      content {
        name          = items.key
        default_value = items.value
        description   = items.key == "MODEL_NAMESPACE" ? "Immutable onboarding boundary; changing this requires a new trusted onboarding." : "Editable non-secret operation argument; model settings must match the validated deployment."
      }
    }
  }
}
resource "oci_devops_deploy_stage" "operation" {
  for_each                        = local.operation_specs
  deploy_pipeline_id              = oci_devops_deploy_pipeline.operation[each.key].id
  display_name                    = "${each.key}-current-model"
  deploy_stage_type               = "SHELL"
  command_spec_deploy_artifact_id = oci_devops_deploy_artifact.operation[each.key].id
  timeout_in_seconds              = 3600
  deploy_stage_predecessor_collection {
    items { id = oci_devops_deploy_pipeline.operation[each.key].id }
  }
  container_config {
    container_config_type = "CONTAINER_INSTANCE_CONFIG"
    compartment_id        = var.compartment_id
    shape_name            = "CI.Standard.E4.Flex"
    shape_config {
      ocpus         = 1
      memory_in_gbs = 8
    }
    network_channel {
      network_channel_type = "SERVICE_VNIC_CHANNEL"
      subnet_id            = var.platform.runner_subnet_id
      nsg_ids              = var.platform.runner_nsg_ids
    }
  }
}
data "oci_core_subnet" "runner" { subnet_id = var.platform.runner_subnet_id }
resource "oci_identity_dynamic_group" "model" {
  provider       = oci.home
  compartment_id = var.tenancy_ocid
  name           = "${local.identity}-pipelines"
  description    = "Exact model-only pipeline identities; Kubernetes RBAC is onboarded by the trusted platform."
  matching_rule  = "ANY {${join(", ", [for id in local.all_pipeline_ids : "resource.id = '${id}'"])}}"
}
resource "oci_identity_policy" "model" {
  provider       = oci.home
  compartment_id = var.tenancy_ocid
  name           = "${local.identity}-pipelines"
  description    = "Model delivery only: cluster access, Shell containers, networking, compartment-scoped Generic Artifacts and the exact OCIR chart repository. No GPU or cluster administration."
  statements = concat([
    "Allow dynamic-group id ${oci_identity_dynamic_group.model.id} to use clusters in compartment id ${var.platform.cluster_compartment_id} where target.cluster.id = '${var.platform.cluster_id}'",
    "Allow dynamic-group id ${oci_identity_dynamic_group.model.id} to read cluster-node-pools in compartment id ${try(var.platform.gpu_pool_compartment_id, var.platform.cluster_compartment_id)}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.model.id} to read devops-family in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.model.id} to manage compute-container-instances in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.model.id} to manage compute-containers in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.model.id} to use virtual-network-family in compartment id ${data.oci_core_subnet.runner.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.model.id} to read artifact-repositories in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.model.id} to read generic-artifacts in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.model.id} to manage generic-artifacts in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.model.id} to use log-content in compartment id ${var.compartment_id}"
  ], [for repo in values(module.delivery.chart_repositories) : "Allow dynamic-group id ${oci_identity_dynamic_group.model.id} to manage repos in compartment id ${var.compartment_id} where target.repo.name = '${repo.name}'"])
}
