# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12" } }
}
data "oci_objectstorage_namespace" "target" { compartment_id = var.tenancy_ocid }
data "oci_core_subnet" "runner" { subnet_id = var.subnet_id }
resource "oci_ons_notification_topic" "pipeline" {
  compartment_id = var.compartment_id
  name           = "${var.name}-pipelines"
}
resource "oci_devops_project" "serving" {
  compartment_id = var.compartment_id
  name           = var.name
  notification_config { topic_id = oci_ons_notification_topic.pipeline.id }
  description = "Pinned model deployment, automatic validation and explicitly triggered benchmarks."
}
resource "oci_logging_log_group" "serving" {
  compartment_id = var.compartment_id
  display_name   = "${var.name}-devops"
}
resource "oci_logging_log" "devops" {
  display_name = "${var.name}-devops"
  log_group_id = oci_logging_log_group.serving.id
  log_type     = "SERVICE"
  is_enabled   = true
  configuration {
    compartment_id = var.compartment_id
    source {
      category    = "all"
      resource    = oci_devops_project.serving.id
      service     = "devops"
      source_type = "OCISERVICE"
    }
  }
}
resource "oci_objectstorage_bucket" "evidence" {
  compartment_id = var.compartment_id
  namespace      = data.oci_objectstorage_namespace.target.namespace
  name           = "${var.name}-${substr(sha256(var.compartment_id), 0, 8)}-evidence"
  access_type    = "NoPublicAccess"
  versioning     = "Enabled"
}
resource "oci_devops_deploy_pipeline" "task" {
  for_each     = toset(["deploy", "validate", "benchmark"])
  project_id   = oci_devops_project.serving.id
  display_name = "${var.name}-${each.key}"
  description  = each.key == "benchmark" ? "Manual benchmark; requires a matching successful validation artifact. May saturate the serving pool." : "${each.key} selected LLM configuration."
}
locals {
  components         = jsondecode(file("${path.module}/../../../catalogs/components.json"))
  specification_hash = sha256(jsonencode({ config = var.config, components = local.components, runner = filesha256("${path.module}/../../../devops/run.sh"), renderer = filesha256("${path.module}/../../../devops/render.jq"), client = filesha256("${path.module}/../../../devops/benchmark.sh") }))
  config = merge(var.config, {
    specification_hash = local.specification_hash
    artifact_bucket    = oci_objectstorage_bucket.evidence.name
    storage_namespace  = data.oci_objectstorage_namespace.target.namespace
    components         = local.components
  })
  command_specs = { for mode in ["deploy", "validate", "benchmark"] : mode => yamlencode({
    version = "0.1", component = "command", timeoutInSeconds = 14400, shell = "bash", failImmediatelyOnError = true
    steps = [{ type = "Command", name = "${mode}-selected-model", timeoutInSeconds = 14400, command = join("\n", [
      "set -euo pipefail",
      "export MODE='${mode}'",
      "export CONFIG_B64='${base64encode(jsonencode(local.config))}'",
      "export RENDER_B64='${filebase64("${path.module}/../../../devops/render.jq")}'",
      "export BENCHMARK_B64='${filebase64("${path.module}/../../../devops/benchmark.sh")}'",
      "printf '%s' '${filebase64("${path.module}/../../../devops/run.sh")}' | base64 --decode > run-serving.sh",
      "bash run-serving.sh",
    ]) }]
  }) }
}
resource "oci_devops_deploy_artifact" "command" {
  for_each                   = local.command_specs
  project_id                 = oci_devops_project.serving.id
  display_name               = "${var.name}-${each.key}-command"
  deploy_artifact_type       = "COMMAND_SPEC"
  argument_substitution_mode = "NONE"
  deploy_artifact_source {
    deploy_artifact_source_type = "INLINE"
    base64encoded_content       = base64encode(each.value)
  }
}
resource "oci_devops_deploy_stage" "task" {
  for_each                        = oci_devops_deploy_pipeline.task
  deploy_pipeline_id              = each.value.id
  display_name                    = each.key
  deploy_stage_type               = "SHELL"
  command_spec_deploy_artifact_id = oci_devops_deploy_artifact.command[each.key].id
  timeout_in_seconds              = 14400
  deploy_stage_predecessor_collection {
    items { id = each.value.id }
  }
  container_config {
    container_config_type = "CONTAINER_INSTANCE_CONFIG"
    shape_name            = "CI.Standard.E4.Flex"
    shape_config {
      ocpus         = 1
      memory_in_gbs = 8
    }
    network_channel {
      network_channel_type = "SERVICE_VNIC_CHANNEL"
      subnet_id            = var.subnet_id
    }
  }
}
resource "oci_devops_deploy_stage" "validate_after_deploy" {
  deploy_pipeline_id              = oci_devops_deploy_pipeline.task["deploy"].id
  display_name                    = "validate-after-deploy"
  deploy_stage_type               = "SHELL"
  command_spec_deploy_artifact_id = oci_devops_deploy_artifact.command["validate"].id
  timeout_in_seconds              = 14400
  deploy_stage_predecessor_collection {
    items { id = oci_devops_deploy_stage.task["deploy"].id }
  }
  container_config {
    container_config_type = "CONTAINER_INSTANCE_CONFIG"
    shape_name            = "CI.Standard.E4.Flex"
    shape_config {
      ocpus         = 1
      memory_in_gbs = 8
    }
    network_channel {
      network_channel_type = "SERVICE_VNIC_CHANNEL"
      subnet_id            = var.subnet_id
    }
  }
}
resource "oci_identity_dynamic_group" "pipelines" {
  compartment_id = var.tenancy_ocid
  name           = "${var.name}-pipelines"
  description    = "Resource principals for these three deployment pipelines only."
  matching_rule  = "ANY {${join(", ", [for pipeline in oci_devops_deploy_pipeline.task : "resource.id = '${pipeline.id}'"])}}"
}
resource "oci_identity_policy" "pipelines" {
  compartment_id = var.tenancy_ocid
  name           = "${var.name}-pipelines"
  description    = "DevOps runner access, cluster authentication and private evidence storage. Kubernetes RBAC is bootstrapped separately."
  statements = [
    "Allow dynamic-group id ${oci_identity_dynamic_group.pipelines.id} to use cluster-family in compartment id ${try(var.config.cluster_compartment_id, var.compartment_id)}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.pipelines.id} to read devops-family in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.pipelines.id} to manage compute-container-instances in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.pipelines.id} to use virtual-network-family in compartment id ${data.oci_core_subnet.runner.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.pipelines.id} to use log-content in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.pipelines.id} to manage objects in compartment id ${var.compartment_id} where target.bucket.name = '${oci_objectstorage_bucket.evidence.name}'",
  ]
}
output "delivery" {
  value = {
    project_id         = oci_devops_project.serving.id
    pipelines          = { for name, pipeline in oci_devops_deploy_pipeline.task : name => pipeline.id }
    artifact_bucket    = oci_objectstorage_bucket.evidence.name
    specification_hash = local.specification_hash
    command_specs      = local.command_specs
    bootstrap_rbac = {
      apiVersion = "v1", kind = "List"
      items = concat([
        { apiVersion = "v1", kind = "Namespace", metadata = { name = var.name } },
        { apiVersion = "v1", kind = "Namespace", metadata = { name = "gpu-operator" } },
        { apiVersion = "rbac.authorization.k8s.io/v1", kind = "ClusterRoleBinding", metadata = { name = "${var.name}-installer" }, roleRef = { apiGroup = "rbac.authorization.k8s.io", kind = "ClusterRole", name = "cluster-admin" }, subjects = [{ kind = "User", name = oci_devops_deploy_pipeline.task["deploy"].id, apiGroup = "rbac.authorization.k8s.io" }] },
        { apiVersion = "rbac.authorization.k8s.io/v1", kind = "ClusterRole", metadata = { name = "${var.name}-node-reader" }, rules = [{ apiGroups = [""], resources = ["nodes"], verbs = ["get", "list", "watch"] }] },
        { apiVersion = "rbac.authorization.k8s.io/v1", kind = "ClusterRoleBinding", metadata = { name = "${var.name}-node-reader" }, roleRef = { apiGroup = "rbac.authorization.k8s.io", kind = "ClusterRole", name = "${var.name}-node-reader" }, subjects = [for name in ["validate", "benchmark"] : { kind = "User", name = oci_devops_deploy_pipeline.task[name].id, apiGroup = "rbac.authorization.k8s.io" }] },
        ], [for namespace in [var.name, "gpu-operator"] : {
          apiVersion = "rbac.authorization.k8s.io/v1", kind = "Role", metadata = { name = "${var.name}-tester", namespace = namespace }
          rules = namespace == var.name ? [
            { apiGroups = [""], resources = ["pods", "pods/log", "services"], verbs = ["get", "list", "watch"] },
            { apiGroups = [""], resources = ["pods/portforward"], verbs = ["create"] },
            { apiGroups = [""], resources = ["configmaps"], verbs = ["get", "create", "patch", "update", "delete"] },
            { apiGroups = ["batch"], resources = ["jobs"], verbs = ["get", "list", "watch", "create", "delete"] },
          ] : [{ apiGroups = [""], resources = ["pods"], verbs = ["get", "list"] }]
          }], [for namespace in [var.name, "gpu-operator"] : {
          apiVersion = "rbac.authorization.k8s.io/v1", kind = "RoleBinding", metadata = { name = "${var.name}-tester", namespace = namespace }
          roleRef    = { apiGroup = "rbac.authorization.k8s.io", kind = "Role", name = "${var.name}-tester" }
          subjects   = [for name in ["validate", "benchmark"] : { kind = "User", name = oci_devops_deploy_pipeline.task[name].id, apiGroup = "rbac.authorization.k8s.io" }]
      }])
    }
  }
}
