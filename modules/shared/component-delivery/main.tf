# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12" } }
}

data "oci_objectstorage_namespace" "registry" { compartment_id = var.compartment_id }

locals {
  managed       = { for key, c in var.components : key => c if c.mode == "managed" }
  scripts       = toset(["archive.sh", "component.sh", "lock.sh", "tools.sh"])
  registry_host = coalesce(var.registry_host, "${var.region}.ocir.io")
  mirror_paths  = { for key, c in local.managed : key => "${var.name}/${substr(sha256(var.cluster_id), 0, 12)}/${key}/${c.chart.name}" }
  specifications = { for key, c in var.components : key => merge(c, {
    component             = key, platform = var.name, cluster_id = var.cluster_id, region = var.region,
    helm_version          = var.helm_version,
    mirror_url            = c.mode == "managed" ? "oci://${local.registry_host}/${data.oci_objectstorage_namespace.registry.namespace}/${local.mirror_paths[key]}" : "",
    lock_name             = "oke-llm-${substr(sha256("${var.cluster_id}/${c.namespace}/${c.release_name}"), 0, 40)}",
    lock_duration_seconds = 3 * c.timeout_seconds + 1800,
    script_digests        = { for script in local.scripts : script => filesha256("${path.module}/scripts/${script}") }
    runtime_digests       = { for path, content in var.runtime_files : path => sha256(content) }
    chart                 = { for key, value in c.chart : key => value if key != "files" }
    chart_digests         = { for path, content in c.chart.files : path => sha256(content) }
  }) }
  generations = { for key, c in local.specifications : key => sha256(jsonencode(c)) }
  # Retire intentionally removes deploy, not undeploy. Removing the map entry
  # removes pipeline definitions only and never uninstalls a release.
  operations = merge(
    { for key, c in var.components : "${key}/deploy" => { component = key, operation = c.mode == "reuse" ? "reuse" : "prepare" } if c.mode != "retire" },
    { for key, c in var.components : "${key}/undeploy" => { component = key, operation = "undeploy" } if c.mode != "reuse" }
  )
  stages = merge(local.operations, { for key, c in local.managed : "${key}/finish" => { component = key, operation = "finish" } })
  parameters = { for key, c in var.components : key => merge(c.parameters, {
    CHART_VERSION           = c.chart.version,
    CONFIRM_UNINSTALL       = "false", RECOVER_LOCK_HOLDER = "none",
    ENFORCE_HELM_DEPLOYMENT = "true"
  }) }
}

resource "oci_artifacts_container_repository" "chart" {
  for_each       = local.managed
  compartment_id = var.compartment_id
  display_name   = local.mirror_paths[each.key]
  is_public      = false
}
resource "oci_generic_artifacts_content_artifact_by_path" "runtime" {
  for_each      = var.runtime_files
  repository_id = var.source_repository_id
  artifact_path = "${var.name}/component-delivery/runtime/${each.key}"
  version       = sha256(each.value)
  content       = each.value
}
locals {
  chart_files    = merge({}, [for key, c in local.managed : { for path, content in c.chart.files : "${key}/${path}" => { component = key, path = path, content = content } }]...)
  values_encoded = { for key, c in local.managed : key => base64encode(c.values_yaml) }
  values_bytes   = { for key, content in local.values_encoded : key => length(content) / 4 * 3 - (endswith(content, "==") ? 2 : endswith(content, "=") ? 1 : 0) }
}
resource "oci_generic_artifacts_content_artifact_by_path" "chart_file" {
  for_each      = local.chart_files
  repository_id = var.source_repository_id
  artifact_path = "${var.name}/components/${each.value.component}/chart/${each.value.path}"
  version       = sha256(each.value.content)
  content       = each.value.content
}
resource "oci_devops_deploy_artifact" "values" {
  for_each                   = local.managed
  project_id                 = var.project_id
  display_name               = "${var.name}-${each.key}-values"
  deploy_artifact_type       = "GENERIC_FILE"
  argument_substitution_mode = "SUBSTITUTE_PLACEHOLDERS"
  deploy_artifact_source {
    deploy_artifact_source_type = "INLINE"
    base64encoded_content       = each.value.values_yaml
  }
  lifecycle {
    precondition {
      condition     = local.values_bytes[each.key] > 0 && local.values_bytes[each.key] <= 51200
      error_message = "Helm values for ${each.key} are ${local.values_bytes[each.key]} UTF-8 bytes; raw content must be nonempty and fit the 51200-byte limit. The OCI provider handles transport encoding."
    }
  }
}
resource "oci_devops_deploy_artifact" "chart" {
  for_each                   = local.managed
  project_id                 = var.project_id
  display_name               = "${var.name}-${each.key}-chart"
  deploy_artifact_type       = "HELM_CHART"
  argument_substitution_mode = "NONE"
  deploy_artifact_source {
    deploy_artifact_source_type = "HELM_CHART"
    chart_url                   = local.specifications[each.key].mirror_url
    deploy_artifact_version     = "$${CHART_VERSION}"
    helm_verification_key_source { verification_key_source_type = "NONE" }
  }
  depends_on = [oci_artifacts_container_repository.chart]
}

resource "oci_devops_deploy_pipeline" "component" {
  for_each     = local.operations
  project_id   = var.project_id
  display_name = "${var.name}-${replace(each.key, "/", "-")}"
  description  = "Independent ${each.value.operation} operation. Component ownership, dependency checks and immutable run evidence; no GPU allocation."
  deploy_pipeline_parameters {
    dynamic "items" {
      for_each = merge(local.parameters[each.value.component], { CONFIRM_UNINSTALL = each.value.operation == "undeploy" ? "true" : "false" })
      content {
        name          = items.key
        default_value = items.value
        description   = items.key == "CHART_VERSION" ? "Explicit upstream chart version; deploy mirrors this version before the native Helm stage." : items.key == "RECOVER_LOCK_HOLDER" ? "Explicit previous deployment OCID; recovery requires expired lease and terminal prior deployment." : items.key == "CONFIRM_UNINSTALL" ? "Defaults true for the dedicated undeploy pipeline and false for other operations." : "Non-secret editable deployment argument. Helm values use matching placeholders."
      }
    }
  }
}

locals {
  command_specs = { for key, stage in local.stages : key => yamlencode({
    version = "0.1", component = "command", timeoutInSeconds = var.components[stage.component].timeout_seconds,
    shell   = "bash", failImmediatelyOnError = true,
    env = { variables = merge(
      { for parameter in keys(local.parameters[stage.component]) : parameter => "$${${parameter}}" },
      {
        DELIVERY_OPERATION     = stage.operation, DELIVERY_GENERATION = local.generations[stage.component],
        DELIVERY_REGION        = var.region,
        DELIVERY_DEPLOYMENT_ID = "$${OCI_DEPLOYMENT_ID}", DELIVERY_PIPELINE_ID = "$${OCI_PIPELINE_ID}",
        DELIVERY_REGISTRY_HOST = local.registry_host, OCI_CLI_AUTH = "resource_principal", OCI_CLI_REGION = var.region
      }
    ) },
    inputArtifacts = concat(
      [for path, artifact in oci_generic_artifacts_content_artifact_by_path.runtime : { name = "runtime-${substr(sha256(path), 0, 16)}", type = "GENERIC_ARTIFACT", location = "./runtime/${path}", artifactId = artifact.artifact_id }],
      [for key, artifact in oci_generic_artifacts_content_artifact_by_path.chart_file : { name = "chart-${substr(sha256(key), 0, 16)}", type = "GENERIC_ARTIFACT", location = "./chart/${local.chart_files[key].path}", artifactId = artifact.artifact_id } if local.chart_files[key].component == stage.component]
    ),
    steps = [{ type = "Command", name = "${stage.operation}-${stage.component}", timeoutInSeconds = var.components[stage.component].timeout_seconds,
      command = join("\n", concat([
        "set -euo pipefail",
        "export ${join(" ", sort(concat(keys(local.parameters[stage.component]), ["DELIVERY_OPERATION", "DELIVERY_GENERATION", "DELIVERY_REGION", "DELIVERY_DEPLOYMENT_ID", "DELIVERY_PIPELINE_ID", "DELIVERY_REGISTRY_HOST", "OCI_CLI_AUTH", "OCI_CLI_REGION", "OCI_DEPLOYMENT_ID", "OCI_PIPELINE_ID"])))}",
        "printf '%s  specification.json\\n' '${local.generations[stage.component]}' | sha256sum -c -"
        ], [for script in sort(tolist(local.scripts)) : "printf '%s  ${script}\\n' '${filesha256("${path.module}/scripts/${script}")}' | sha256sum -c -"],
        [for path, content in var.runtime_files : "printf '%s  runtime/${path}\\n' '${sha256(content)}' | sha256sum -c -"],
      [for path, content in var.components[stage.component].chart.files : "printf '%s  chart/${path}\\n' '${sha256(content)}' | sha256sum -c -"], ["bash ./component.sh"]))
    }]
  }) }
}
module "inline_command" {
  for_each      = local.stages
  source        = "../inline-command-spec"
  specification = yamldecode(local.command_specs[each.key])
  files = merge({ for script in local.scripts : script => file("${path.module}/scripts/${script}") }, {
    "specification.json" = jsonencode(local.specifications[each.value.component])
  })
}
resource "oci_devops_deploy_artifact" "command" {
  for_each                   = local.stages
  project_id                 = var.project_id
  display_name               = "${var.name}-${replace(each.key, "/", "-")}-command"
  deploy_artifact_type       = "COMMAND_SPEC"
  argument_substitution_mode = "NONE"
  deploy_artifact_source {
    deploy_artifact_source_type = "INLINE"
    # The OCI provider maps this text to Go []byte; the SDK handles JSON
    # base64 encoding. Passing base64encode(...) would encode it twice.
    base64encoded_content = module.inline_command[each.key].content
  }
}
resource "oci_devops_deploy_stage" "shell" {
  for_each                        = local.operations
  deploy_pipeline_id              = oci_devops_deploy_pipeline.component["${each.value.component}/${each.value.operation == "undeploy" ? "undeploy" : "deploy"}"].id
  display_name                    = "${each.value.operation}-${each.value.component}"
  deploy_stage_type               = "SHELL"
  command_spec_deploy_artifact_id = oci_devops_deploy_artifact.command[each.key].id
  timeout_in_seconds              = var.components[each.value.component].timeout_seconds
  deploy_stage_predecessor_collection {
    items {
      id = oci_devops_deploy_pipeline.component[each.key].id
    }
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
      subnet_id            = var.subnet_id
      nsg_ids              = var.nsg_ids
    }
  }
}
resource "oci_devops_deploy_stage" "finish" {
  for_each                        = local.managed
  deploy_pipeline_id              = oci_devops_deploy_pipeline.component["${each.key}/deploy"].id
  display_name                    = "validate-${each.key}"
  deploy_stage_type               = "SHELL"
  command_spec_deploy_artifact_id = oci_devops_deploy_artifact.command["${each.key}/finish"].id
  timeout_in_seconds              = each.value.timeout_seconds
  deploy_stage_predecessor_collection {
    items { id = oci_devops_deploy_stage.helm[each.key].id }
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
      subnet_id            = var.subnet_id
      nsg_ids              = var.nsg_ids
    }
  }
}
resource "oci_devops_deploy_stage" "helm" {
  for_each                          = local.managed
  deploy_pipeline_id                = oci_devops_deploy_pipeline.component["${each.key}/deploy"].id
  display_name                      = "helm-${each.key}"
  deploy_stage_type                 = "OKE_HELM_CHART_DEPLOYMENT"
  purpose                           = "EXECUTE_HELM_UPGRADE"
  oke_cluster_deploy_environment_id = var.cluster_deploy_environment_id
  helm_chart_deploy_artifact_id     = oci_devops_deploy_artifact.chart[each.key].id
  values_artifact_ids               = [oci_devops_deploy_artifact.values[each.key].id]
  release_name                      = each.value.release_name
  namespace                         = each.value.namespace
  timeout_in_seconds                = each.value.timeout_seconds
  is_uninstall_on_stage_delete      = false
  is_force_enabled                  = false
  should_not_wait                   = false
  should_skip_crds                  = !each.value.manage_crds
  should_reset_values               = true
  should_reuse_values               = false
  are_hooks_enabled                 = true
  max_history                       = 10
  rollback_policy { policy_type = "AUTOMATED_STAGE_ROLLBACK_POLICY" }
  deploy_stage_predecessor_collection {
    items { id = oci_devops_deploy_stage.shell["${each.key}/deploy"].id }
  }
}
