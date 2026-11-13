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
  generation = sha256(jsonencode({ specification = var.config, components = local.components, runner = filesha256("${path.module}/scripts/bootstrap.sh"), readiness = filesha256("${path.module}/scripts/readiness.jq") }))
  config = merge(var.config, {
    generation      = local.generation, components = local.components, storage_namespace = data.oci_objectstorage_namespace.target.namespace,
    artifact_bucket = oci_objectstorage_bucket.platform.name, evidence_prefix = "${var.name}/${local.generation}"
  })
  command_spec = yamlencode({
    version = "0.1", component = "command", timeoutInSeconds = 3600, shell = "bash", failImmediatelyOnError = true,
    steps = [{ type = "Command", name = "bootstrap-shared-platform", timeoutInSeconds = 3600, command = join("\n", [
      "set -euo pipefail",
      "export CONFIG_B64='${base64encode(jsonencode(local.config))}'",
      "export READINESS_B64='${filebase64("${path.module}/scripts/readiness.jq")}'",
      "printf '%s' '${filebase64("${path.module}/scripts/bootstrap.sh")}' | base64 --decode > bootstrap-platform.sh",
      "bash bootstrap-platform.sh"
    ]) }]
  })
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
  display_name = "${var.name}-bootstrap"
  description  = "Explicit shared-platform bootstrap. Does not deploy any model or release GPU hosts."
}
resource "oci_devops_deploy_artifact" "bootstrap" {
  project_id                 = oci_devops_project.platform.id
  display_name               = "${var.name}-bootstrap-command"
  deploy_artifact_type       = "COMMAND_SPEC"
  argument_substitution_mode = "NONE"
  deploy_artifact_source {
    deploy_artifact_source_type = "INLINE"
    base64encoded_content       = base64encode(local.command_spec)
  }
}
resource "oci_devops_deploy_stage" "bootstrap" {
  deploy_pipeline_id              = oci_devops_deploy_pipeline.bootstrap.id
  display_name                    = "bootstrap-shared-platform"
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
resource "oci_identity_dynamic_group" "bootstrap" {
  provider       = oci.home
  compartment_id = var.tenancy_ocid
  name           = "${var.name}-bootstrap"
  description    = "Platform bootstrap pipeline resource principal only."
  matching_rule  = "ALL {resource.id = '${oci_devops_deploy_pipeline.bootstrap.id}'}"
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
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to use virtual-network-family in compartment id ${data.oci_core_subnet.runner.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to use log-content in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to manage objects in compartment id ${var.compartment_id} where target.bucket.name = '${oci_objectstorage_bucket.platform.name}'"
  ]
}
output "bootstrap_rbac" {
  value = {
    apiVersion = "rbac.authorization.k8s.io/v1", kind = "ClusterRoleBinding", metadata = { name = "${var.name}-bootstrap" },
    roleRef    = { apiGroup = "rbac.authorization.k8s.io", kind = "ClusterRole", name = "cluster-admin" },
    subjects   = [{ kind = "User", name = oci_devops_deploy_pipeline.bootstrap.id, apiGroup = "rbac.authorization.k8s.io" }]
  }
}
output "platform" {
  value = {
    schema_version    = "1.0", platform_name = var.name, generation = local.generation, region = var.config.region, cluster_id = var.config.cluster_id,
    allocation        = var.config.allocation, gpu_shape = var.config.gpu_shape, node_count = var.config.node_count, gpu_count_per_host = var.config.gpu_count_per_host,
    validation_scope  = try(var.config.gpu_allocation_enabled, true) ? "platform_and_gpu_capacity" : "cpu_components_only",
    gpu_selector      = "oke-llm/allocation=${var.name}", cpu_placement = "existing_cluster_cpu_pools",
    project_id        = oci_devops_project.platform.id, bootstrap_pipeline_id = oci_devops_deploy_pipeline.bootstrap.id,
    specification_uri = "oci://${var.config.region}/${data.oci_objectstorage_namespace.target.namespace}/${oci_objectstorage_bucket.platform.name}/${oci_objectstorage_object.specification.object}",
    readiness_uri     = "oci://${var.config.region}/${data.oci_objectstorage_namespace.target.namespace}/${oci_objectstorage_bucket.platform.name}/${local.config.evidence_prefix}/readiness.json",
    runtime_readiness = "read_generation_specific_pipeline_evidence; Terraform does not assert ready"
  }
}
