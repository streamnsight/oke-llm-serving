# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12", configuration_aliases = [oci.home] } }
}
data "oci_objectstorage_namespace" "target" { compartment_id = var.tenancy_ocid }
data "oci_core_subnet" "runner" { subnet_id = var.subnet_id }
resource "oci_ons_notification_topic" "platform" {
  compartment_id = var.compartment_id
  name           = "${var.name}-platform"
}
resource "oci_devops_project" "platform" {
  compartment_id = var.compartment_id
  name           = var.name
  description    = "Shared LLM platform foundation; model pipelines can reference this project later."
  notification_config { topic_id = oci_ons_notification_topic.platform.id }
  lifecycle {
    precondition {
      condition     = try(var.config.target.ready, true)
      error_message = "The cluster target must pass discovery checks before creating the platform project."
    }
  }
}
resource "oci_logging_log_group" "platform" {
  compartment_id = var.compartment_id
  display_name   = "${var.name}-platform"
}
resource "oci_logging_log" "platform" {
  display_name = "${var.name}-platform"
  log_group_id = oci_logging_log_group.platform.id
  log_type     = "SERVICE"
  is_enabled   = true
  configuration {
    compartment_id = var.compartment_id
    source {
      category    = "all"
      resource    = oci_devops_project.platform.id
      service     = "devops"
      source_type = "OCISERVICE"
    }
  }
}
resource "oci_objectstorage_bucket" "platform" {
  compartment_id = var.compartment_id
  namespace      = data.oci_objectstorage_namespace.target.namespace
  name           = "${var.name}-${substr(sha256(var.compartment_id), 0, 8)}-platform"
  access_type    = "NoPublicAccess"
  versioning     = "Enabled"
}
locals {
  components = jsondecode(file("${path.module}/data/components.json"))
  scripts    = toset(["bootstrap.sh", "config.jq", "lws.sh", "readiness.jq"])
  settings = {
    PLATFORM_NAME          = var.name, REGION = var.config.region, CLUSTER_ID = var.config.cluster_id,
    KUBERNETES_VERSION     = var.config.target.kubernetes_version, HELM_VERSION = local.components.helm_version,
    GPU_ALLOCATION_ENABLED = tostring(try(var.config.gpu_allocation_enabled, true)), GPU_NODE_COUNT = tostring(var.config.node_count),
    GPUS_PER_HOST          = tostring(var.config.gpu_count_per_host), GPU_SHAPES = join(",", try(var.config.gpu_shapes, [var.config.gpu_shape])),
    REQUIRES_RDMA          = tostring(try(var.config.requires_rdma, false)), RDMA_RESOURCE_NAME = try(coalesce(var.config.rdma_resource_name, "auto"), "auto"),
    ENABLE_LWS             = tostring(try(var.config.enable_lws, true)), LWS_CHART = local.components.lws.chart,
    LWS_VERSION            = local.components.lws.version, LWS_RELEASE = local.components.lws.release, LWS_NAMESPACE = local.components.lws.namespace
  }
  parameters = merge(local.settings, { LWS_OPERATION = "ensure" })
  generation = sha256(jsonencode({ specification = var.config, settings = local.settings, scripts = { for script in local.scripts : script => filesha256("${path.module}/scripts/${script}") } }))
  config = merge(var.config, {
    generation      = local.generation, components = local.components, storage_namespace = data.oci_objectstorage_namespace.target.namespace,
    artifact_bucket = oci_objectstorage_bucket.platform.name, evidence_prefix = "${var.name}/${local.generation}"
  })
  command_specs = { for mode in ["deploy", "validate"] : mode => yamlencode({
    version = "0.1", component = "command", timeoutInSeconds = 3600, shell = "bash", failImmediatelyOnError = true,
    env = { variables = merge({ for key in keys(local.parameters) : key => "$${${key}}" }, {
      PLATFORM_MODE     = mode, PLATFORM_GENERATION = local.generation, EXPECTED_SETTINGS_SHA256 = sha256(jsonencode(local.settings)),
      STORAGE_NAMESPACE = data.oci_objectstorage_namespace.target.namespace, ARTIFACT_BUCKET = oci_objectstorage_bucket.platform.name,
      EVIDENCE_PREFIX   = local.config.evidence_prefix, OCI_CLI_AUTH = "resource_principal", OCI_CLI_REGION = "$${REGION}"
    }) },
    steps = [{ type = "Command", name = mode == "deploy" ? "deploy-leaderworkerset" : "validate-platform", timeoutInSeconds = 3600, command = join("\n", concat([
      "set -euo pipefail", "runtime_dir=$(mktemp -d)", "trap 'rm -rf \"$runtime_dir\"' EXIT", "cd \"$runtime_dir\""
      ], flatten([for script in sort(tolist(local.scripts)) : [
        "oci os object get --namespace-name \"$STORAGE_NAMESPACE\" --bucket-name \"$ARTIFACT_BUCKET\" --name '${oci_objectstorage_object.script[script].object}' --file '${script}'",
        "printf '%s  %s\\n' '${filesha256("${path.module}/scripts/${script}")}' '${script}' | sha256sum -c -"
    ]]), ["bash bootstrap.sh"])) }]
  }) }
}
resource "oci_objectstorage_object" "script" {
  for_each     = local.scripts
  namespace    = data.oci_objectstorage_namespace.target.namespace
  bucket       = oci_objectstorage_bucket.platform.name
  object       = "${var.name}/scripts/${filesha256("${path.module}/scripts/${each.key}")}/${each.key}"
  content      = file("${path.module}/scripts/${each.key}")
  content_type = "text/plain"
}
resource "oci_objectstorage_object" "specification" {
  namespace    = data.oci_objectstorage_namespace.target.namespace
  bucket       = oci_objectstorage_bucket.platform.name
  object       = "${var.name}/platform-spec.json"
  content      = jsonencode(local.config)
  content_type = "application/json"
}
resource "oci_devops_deploy_pipeline" "bootstrap" {
  project_id   = oci_devops_project.platform.id
  display_name = "${var.name}-lws"
  description  = "Deploy/reuse LWS independently. LWS_OPERATION=upgrade explicitly updates the configured Helm release and CRDs. No model or node changes."
  deploy_pipeline_parameters {
    dynamic "items" {
      for_each = local.parameters
      content {
        name          = items.key
        default_value = items.value
        description   = items.key == "LWS_OPERATION" ? "ensure reuses a healthy matching release; upgrade explicitly updates the configured release and CRDs." : "Non-secret Shell environment setting. Override for a run; changed settings get separate readiness evidence."
      }
    }
  }
}
resource "oci_devops_deploy_artifact" "bootstrap" {
  project_id                 = oci_devops_project.platform.id
  display_name               = "${var.name}-bootstrap-command"
  deploy_artifact_type       = "COMMAND_SPEC"
  argument_substitution_mode = "NONE"
  deploy_artifact_source {
    deploy_artifact_source_type = "INLINE"
    base64encoded_content       = base64encode(local.command_specs.deploy)
  }
}
resource "oci_devops_deploy_stage" "bootstrap" {
  deploy_pipeline_id              = oci_devops_deploy_pipeline.bootstrap.id
  display_name                    = "deploy-leaderworkerset"
  deploy_stage_type               = "SHELL"
  command_spec_deploy_artifact_id = oci_devops_deploy_artifact.bootstrap.id
  timeout_in_seconds              = 3600
  deploy_stage_predecessor_collection {
    items { id = oci_devops_deploy_pipeline.bootstrap.id }
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
resource "oci_devops_deploy_pipeline" "validate" {
  project_id   = oci_devops_project.platform.id
  display_name = "${var.name}-validate"
  description  = "Read-only node/controller validation and admission dry run. Writes evidence but never installs/upgrades components."
  deploy_pipeline_parameters {
    dynamic "items" {
      for_each = local.parameters
      content {
        name          = items.key
        default_value = items.value
        description   = items.key == "LWS_OPERATION" ? "Ignored by this read-only pipeline." : "Non-secret Shell environment setting; overrides get separate evidence."
      }
    }
  }
}
resource "oci_devops_deploy_artifact" "validate" {
  project_id                 = oci_devops_project.platform.id
  display_name               = "${var.name}-validate-command"
  deploy_artifact_type       = "COMMAND_SPEC"
  argument_substitution_mode = "NONE"
  deploy_artifact_source {
    deploy_artifact_source_type = "INLINE"
    base64encoded_content       = base64encode(local.command_specs.validate)
  }
}
resource "oci_devops_deploy_stage" "validate" {
  deploy_pipeline_id              = oci_devops_deploy_pipeline.validate.id
  display_name                    = "validate-platform"
  deploy_stage_type               = "SHELL"
  command_spec_deploy_artifact_id = oci_devops_deploy_artifact.validate.id
  timeout_in_seconds              = 3600
  deploy_stage_predecessor_collection {
    items { id = oci_devops_deploy_pipeline.validate.id }
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
resource "oci_identity_dynamic_group" "bootstrap" {
  provider       = oci.home
  compartment_id = var.tenancy_ocid
  name           = "${var.name}-bootstrap"
  description    = "Platform bootstrap pipeline resource principal only."
  matching_rule  = "ANY {resource.id = '${oci_devops_deploy_pipeline.bootstrap.id}', resource.id = '${oci_devops_deploy_pipeline.validate.id}'}"
}
resource "oci_identity_policy" "bootstrap" {
  provider       = oci.home
  compartment_id = var.tenancy_ocid
  name           = "${var.name}-bootstrap"
  description    = "OCI access for private platform bootstrap; Kubernetes authorization is explicit."
  statements = [
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to use cluster-family in compartment id ${var.config.target.cluster_compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to read devops-family in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to manage compute-container-instances in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to manage compute-containers in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to use virtual-network-family in compartment id ${data.oci_core_subnet.runner.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to use log-content in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to manage objects in compartment id ${var.compartment_id} where target.bucket.name = '${oci_objectstorage_bucket.platform.name}'"
  ]
}
output "bootstrap_rbac" {
  value = {
    apiVersion = "rbac.authorization.k8s.io/v1", kind = "ClusterRoleBinding", metadata = { name = "${var.name}-bootstrap" },
    roleRef    = { apiGroup = "rbac.authorization.k8s.io", kind = "ClusterRole", name = "cluster-admin" },
    subjects   = [for id in [oci_devops_deploy_pipeline.bootstrap.id, oci_devops_deploy_pipeline.validate.id] : { kind = "User", name = id, apiGroup = "rbac.authorization.k8s.io" }]
  }
}
output "platform" {
  value = {
    schema_version         = "1.0", platform_name = var.name, generation = local.generation, region = var.config.region, cluster_id = var.config.cluster_id,
    allocation             = var.config.allocation, gpu_shape = var.config.gpu_shape, node_count = var.config.node_count, gpu_count_per_host = var.config.gpu_count_per_host,
    validation_scope       = try(var.config.gpu_allocation_enabled, true) ? "platform_and_gpu_capacity" : "cpu_components_only",
    gpu_selector           = "oke-llm/allocation=${var.name}", cpu_placement = "existing_cluster_cpu_pools",
    project_id             = oci_devops_project.platform.id, bootstrap_pipeline_id = oci_devops_deploy_pipeline.bootstrap.id,
    component_pipeline_ids = { lws = oci_devops_deploy_pipeline.bootstrap.id }, validation_pipeline_id = oci_devops_deploy_pipeline.validate.id,
    specification_uri      = "oci://${var.config.region}/${data.oci_objectstorage_namespace.target.namespace}/${oci_objectstorage_bucket.platform.name}/${oci_objectstorage_object.specification.object}",
    readiness_uri          = "oci://${var.config.region}/${data.oci_objectstorage_namespace.target.namespace}/${oci_objectstorage_bucket.platform.name}/${local.config.evidence_prefix}/readiness.json",
    runtime_readiness      = "read_generation_specific_pipeline_evidence; Terraform does not assert ready"
  }
}
