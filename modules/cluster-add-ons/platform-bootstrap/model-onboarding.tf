# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  model_onboarding_scripts = toset(["onboard-model.sh", "model-access.jq"])
  model_onboarding_parameters = {
    MODEL_NAMESPACE = "", MODEL_PIPELINE_IDS = "[]", MODEL_PROJECT_ID = "", MODEL_GPU_POOL_ID = "runtime", MODEL_ACCESS_OPERATION = "grant"
  }
  model_onboarding_context = jsonencode({ components = { for key, c in local.component_specs : key => {
    namespace    = c.namespace, mode = c.mode, owner_name = module.components.owner_names[key], ownership_token = c.ownership_token,
    release_name = c.release_name, crd_names = c.crd_names, deployment_names = c.deployment_names
  } } })
  model_onboarding_command = yamlencode({
    version = "0.1", component = "command", timeoutInSeconds = 1800, shell = "bash", failImmediatelyOnError = true,
    env = { variables = merge({ for name in keys(local.model_onboarding_parameters) : name => "$${${name}}" }, {
      PLATFORM_NAME      = var.name, CLUSTER_ID = var.config.cluster_id, PROJECT_ID = oci_devops_project.platform.id,
      KUBERNETES_VERSION = var.config.target.kubernetes_version,
      OCI_CLI_AUTH       = "resource_principal", OCI_CLI_REGION = var.config.region
    }) },
    inputArtifacts = [],
    steps = [{ type = "Command", name = "authorize-exact-model-pipelines", timeoutInSeconds = 1800, command = join("\n", concat([
      "set -euo pipefail",
      "export MODEL_NAMESPACE MODEL_PIPELINE_IDS MODEL_PROJECT_ID MODEL_GPU_POOL_ID MODEL_ACCESS_OPERATION PLATFORM_NAME CLUSTER_ID PROJECT_ID KUBERNETES_VERSION OCI_CLI_AUTH OCI_CLI_REGION"
    ], [for script in sort(tolist(local.model_onboarding_scripts)) : "printf '%s  %s\\n' '${filesha256("${path.module}/scripts/${script}")}' '${script}' | sha256sum -c -"], ["printf '%s  model-access-context.json\\n' '${sha256(local.model_onboarding_context)}' | sha256sum -c -", "bash ./onboard-model.sh"])) }]
  })
}
module "inline_onboarding" {
  source        = "../../shared/inline-command-spec"
  specification = yamldecode(local.model_onboarding_command)
  files         = merge({ for script in local.model_onboarding_scripts : script => file("${path.module}/scripts/${script}") }, { "model-access-context.json" = local.model_onboarding_context })
}
resource "oci_devops_deploy_pipeline" "model_onboarding" {
  project_id   = oci_devops_project.platform.id
  display_name = "${var.name}-model-onboarding"
  description  = "Trusted CPU-only namespace/RBAC onboarding for exact model pipelines in an explicitly selected independent model project. Never deploys models or changes GPU infrastructure. Revoke requires no active Pods."
  deploy_pipeline_parameters {
    dynamic "items" {
      for_each = local.model_onboarding_parameters
      content {
        name          = items.key
        default_value = items.value
        description   = "Use the model stack's onboarding_arguments. Namespace must belong to this platform; active pipeline defaults must declare that model project, cluster, platform, GPU pool and namespace. grant or revoke is explicit."
      }
    }
  }
}
resource "oci_devops_deploy_artifact" "model_onboarding" {
  project_id                 = oci_devops_project.platform.id
  display_name               = "${var.name}-model-onboarding-command"
  deploy_artifact_type       = "COMMAND_SPEC"
  argument_substitution_mode = "NONE"
  deploy_artifact_source {
    deploy_artifact_source_type = "INLINE"
    base64encoded_content       = module.inline_onboarding.content
  }
}
resource "oci_devops_deploy_stage" "model_onboarding" {
  deploy_pipeline_id              = oci_devops_deploy_pipeline.model_onboarding.id
  display_name                    = "authorize-exact-model-pipelines"
  deploy_stage_type               = "SHELL"
  command_spec_deploy_artifact_id = oci_devops_deploy_artifact.model_onboarding.id
  timeout_in_seconds              = 1800
  deploy_stage_predecessor_collection {
    items { id = oci_devops_deploy_pipeline.model_onboarding.id }
  }
  container_config {
    container_config_type = "CONTAINER_INSTANCE_CONFIG"
    compartment_id        = var.compartment_id
    shape_name            = "CI.Standard.E4.Flex"
    shape_config {
      ocpus         = 1
      memory_in_gbs = 4
    }
    network_channel {
      network_channel_type = "SERVICE_VNIC_CHANNEL"
      subnet_id            = var.subnet_id
      nsg_ids              = var.nsg_ids
    }
  }
}
