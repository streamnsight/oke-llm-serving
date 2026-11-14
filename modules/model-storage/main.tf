# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12", configuration_aliases = [oci.home] } }
}
locals {
  enabled   = var.mode == "object_storage"
  namespace = coalesce(var.namespace, "${var.name}-staging")
  owner     = substr(sha256(jsonencode([var.compartment_id, var.cluster_id, var.name])), 0, 24)
  model     = var.model == null ? { id = "unset/unset", revision = "", variant = "unset", files = [] } : var.model
  snapshot  = sha256(jsonencode(local.model))
  prefix    = "models/${replace(local.model.id, "/", "--")}/${local.model.revision}/${local.model.variant}/${local.snapshot}"
  labels    = { "app.kubernetes.io/managed-by" = "oke-llm-serving", "oke-llm/storage-owner" = local.owner }
  pvc_name  = "${var.name}-download"
  scripts   = toset(["stage.sh", "download.sh", "validate.jq", "job.jq"])
}
resource "terraform_data" "requirements" {
  count = local.enabled ? 1 : 0
  lifecycle {
    precondition {
      condition     = alltrue([for v in [var.tenancy_ocid, var.compartment_id, var.project_id, var.artifact_repository_id, var.cluster_id, var.cluster_compartment_id, var.region, var.subnet_id] : try(length(v) > 0, false)]) && var.model != null
      error_message = "Object Storage staging requires a pinned file manifest, existing DevOps project/Generic Artifact repository, cluster identity, region, tenancy/compartment and private runner subnet."
    }
    precondition {
      condition     = var.cluster_type == "ENHANCED_CLUSTER" && can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
      error_message = "Staging uses OKE workload identity: select an enhanced cluster and its exact vMAJOR.MINOR.PATCH Kubernetes version."
    }
    precondition {
      condition     = var.staging_image != null
      error_message = "Set staging_image to a tested digest-pinned image built from modules/model-storage/image/Dockerfile. No unverified default image is assumed."
    }
    precondition {
      condition     = length(var.cpu_node_selector) > 0 && length(jsonencode(local.model)) < 262144
      error_message = "Select a confirmed CPU node pool and provide a snapshot file manifest below 256 KiB."
    }
    precondition {
      condition     = try(var.scratch_gib * pow(1024, 3) >= max(concat([0], [for f in local.model.files : f.size_bytes])...) * 1.1 + 67108864, false)
      error_message = "The scratch PVC must fit the largest selected file plus 10 percent and 64 MiB of headroom."
    }
  }
}
data "oci_objectstorage_namespace" "model" {
  count          = local.enabled ? 1 : 0
  compartment_id = var.tenancy_ocid
}
data "oci_core_subnet" "runner" {
  count     = local.enabled ? 1 : 0
  subnet_id = var.subnet_id
}
resource "oci_objectstorage_bucket" "weights" {
  count          = local.enabled ? 1 : 0
  compartment_id = var.compartment_id
  namespace      = data.oci_objectstorage_namespace.model[0].namespace
  name           = "${var.name}-${local.owner}-weights"
  access_type    = "NoPublicAccess"
  versioning     = "Enabled"
  storage_tier   = "Standard"
  lifecycle { prevent_destroy = true }
  depends_on = [terraform_data.requirements]
}
locals {
  config = local.enabled ? jsonencode({
    schema_version = "1.0", model = local.model, snapshot_sha256 = local.snapshot,
    region         = var.region, storage_namespace = data.oci_objectstorage_namespace.model[0].namespace,
    bucket         = oci_objectstorage_bucket.weights[0].name, prefix = local.prefix, owner = local.owner,
    namespace      = local.namespace, service_account = var.service_account, pvc_name = local.pvc_name,
    scratch_gib    = var.scratch_gib, storage_class = var.storage_class, cpu_node_selector = var.cpu_node_selector, hf_token_secret_id = var.hf_token_secret_id
  }) : "{}"
  artifact_contents = local.enabled ? merge({ "model.json" = local.config }, { for s in local.scripts : s => file("${path.module}/scripts/${s}") }) : {}
  parameters        = { STAGING_IMAGE = coalesce(var.staging_image, "unset"), JOB_DEADLINE_SECONDS = tostring(var.deadline_seconds) }
  command_spec = local.enabled ? yamlencode({
    version = "0.1", component = "command", shell = "bash", timeoutInSeconds = 28800, failImmediatelyOnError = true,
    env = { variables = {
      STAGING_IMAGE       = "$${STAGING_IMAGE}", JOB_DEADLINE_SECONDS = "$${JOB_DEADLINE_SECONDS}",
      MODEL_STAGE_NAME    = var.name, CLUSTER_ID = var.cluster_id, KUBERNETES_VERSION = var.kubernetes_version,
      MODEL_CONFIG_SHA256 = sha256(local.config), RESULT_REPOSITORY_ID = coalesce(var.result_repository_id, var.artifact_repository_id),
      OCI_CLI_AUTH        = "resource_principal", OCI_CLI_REGION = var.region
    } },
    inputArtifacts = [for name, artifact in oci_generic_artifacts_content_artifact_by_path.input : {
      name       = replace(name, ".", "-"), type = "GENERIC_ARTIFACT", artifactId = artifact.artifact_id,
      registryId = var.artifact_repository_id, path = artifact.artifact_path, version = artifact.version, location = "./${name}"
    }],
    steps = [{ type = "Command", name = "stage-model-on-cpu", timeoutInSeconds = 28800, command = join("\n", concat([
      "set -euo pipefail",
      "export STAGING_IMAGE JOB_DEADLINE_SECONDS MODEL_STAGE_NAME CLUSTER_ID KUBERNETES_VERSION MODEL_CONFIG_SHA256 RESULT_REPOSITORY_ID OCI_CLI_AUTH OCI_CLI_REGION"
    ], [for name, content in local.artifact_contents : "printf '%s  %s\\n' '${sha256(content)}' '${name}' | sha256sum -c -"], ["bash ./stage.sh"])) }]
  }) : null
}
resource "oci_generic_artifacts_content_artifact_by_path" "input" {
  for_each      = local.artifact_contents
  repository_id = var.artifact_repository_id
  artifact_path = "model-storage/${var.name}/${each.key}"
  version       = sha256(each.value)
  content       = each.value
}
resource "oci_devops_deploy_pipeline" "stage" {
  count        = local.enabled ? 1 : 0
  project_id   = var.project_id
  display_name = "${var.name}-stage-weights"
  description  = "Explicit CPU-only Hugging Face snapshot staging. Does not deploy a model, allocate GPUs or purge weights. Bootstrap Kubernetes RBAC/PVC first."
  deploy_pipeline_parameters {
    dynamic "items" {
      for_each = local.parameters
      content {
        name          = items.key
        default_value = items.value
        description   = "Editable non-secret Job setting. Effective values are recorded in the run report; model file identity is immutable artifact input."
      }
    }
  }
  depends_on = [terraform_data.requirements]
}
resource "oci_devops_deploy_artifact" "stage" {
  count                      = local.enabled ? 1 : 0
  project_id                 = var.project_id
  display_name               = "${var.name}-stage-weights-command"
  deploy_artifact_type       = "COMMAND_SPEC"
  argument_substitution_mode = "NONE"
  deploy_artifact_source {
    deploy_artifact_source_type = "INLINE"
    base64encoded_content       = base64encode(local.command_spec)
  }
}
resource "oci_devops_deploy_stage" "stage" {
  count                           = local.enabled ? 1 : 0
  deploy_pipeline_id              = oci_devops_deploy_pipeline.stage[0].id
  display_name                    = "stage-model-on-cpu"
  deploy_stage_type               = "SHELL"
  command_spec_deploy_artifact_id = oci_devops_deploy_artifact.stage[0].id
  timeout_in_seconds              = 28800
  deploy_stage_predecessor_collection {
    items { id = oci_devops_deploy_pipeline.stage[0].id }
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
  depends_on = [oci_identity_policy.runner, oci_identity_policy.workload]
}
resource "oci_identity_dynamic_group" "runner" {
  provider       = oci.home
  count          = local.enabled ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = "${var.name}-${local.owner}-model-stage"
  description    = "DevOps Shell runner only; never inherited by the Kubernetes download Job."
  matching_rule  = "ALL {resource.id = '${oci_devops_deploy_pipeline.stage[0].id}'}"
}
resource "oci_identity_policy" "runner" {
  provider       = oci.home
  count          = local.enabled ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = "${var.name}-${local.owner}-model-stage"
  description    = "Runner cluster/artifact access; no model bucket or Vault permissions. Kubernetes authorization is bootstrapped separately."
  statements = [
    "Allow dynamic-group id ${oci_identity_dynamic_group.runner[0].id} to use cluster-family in compartment id ${var.cluster_compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.runner[0].id} to read devops-family in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.runner[0].id} to manage compute-container-instances in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.runner[0].id} to manage compute-containers in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.runner[0].id} to use virtual-network-family in compartment id ${data.oci_core_subnet.runner[0].compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.runner[0].id} to read artifact-repositories in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.runner[0].id} to manage generic-artifacts in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.runner[0].id} to use log-content in compartment id ${var.compartment_id}"
  ]
}
locals {
  workload_condition = "request.principal.type = 'workload', request.principal.namespace = '${local.namespace}', request.principal.service_account = '${var.service_account}', request.principal.cluster_id = '${coalesce(var.cluster_id, "unset")}'"
}
resource "oci_identity_policy" "workload" {
  provider       = oci.home
  count          = local.enabled ? 1 : 0
  compartment_id = var.tenancy_ocid
  name           = "${var.name}-${local.owner}-model-storage"
  description    = "Enhanced OKE service-account identity, not a dynamic group or node principal. No model-delete permission."
  statements = concat([
    "Allow any-user to read buckets in compartment id ${var.compartment_id} where all {${local.workload_condition}, target.bucket.name = '${oci_objectstorage_bucket.weights[0].name}'}",
    "Allow any-user to {OBJECT_INSPECT, OBJECT_READ, OBJECT_CREATE, OBJECT_OVERWRITE} in compartment id ${var.compartment_id} where all {${local.workload_condition}, target.bucket.name = '${oci_objectstorage_bucket.weights[0].name}'}"
    ], var.hf_token_secret_id == null ? [] : [
    "Allow any-user to read secret-bundles in compartment id ${coalesce(var.hf_token_secret_compartment_id, var.compartment_id)} where all {${local.workload_condition}, target.secret.id = '${var.hf_token_secret_id}'}"
  ])
}
locals {
  bootstrap_manifest = local.enabled ? {
    apiVersion = "v1", kind = "List", items = [
      { apiVersion = "v1", kind = "Namespace", metadata = { name = local.namespace, labels = local.labels } },
      { apiVersion = "v1", kind = "ServiceAccount", metadata = { name = var.service_account, namespace = local.namespace, labels = local.labels }, automountServiceAccountToken = true },
      { apiVersion = "v1", kind = "PersistentVolumeClaim", metadata = { name = local.pvc_name, namespace = local.namespace, labels = local.labels }, spec = { accessModes = ["ReadWriteOnce"], storageClassName = var.storage_class, resources = { requests = { storage = "${var.scratch_gib}Gi" } } } },
      { apiVersion = "rbac.authorization.k8s.io/v1", kind = "Role", metadata = { name = "${var.name}-stage-runner", namespace = local.namespace, labels = local.labels }, rules = [
        { apiGroups = [""], resources = ["pods", "pods/log", "persistentvolumeclaims", "serviceaccounts"], verbs = ["get", "list", "watch"] },
        { apiGroups = [""], resources = ["configmaps"], verbs = ["get", "create", "delete"] },
        { apiGroups = ["batch"], resources = ["jobs"], verbs = ["get", "create", "delete"] }
      ] },
      { apiVersion = "rbac.authorization.k8s.io/v1", kind = "RoleBinding", metadata = { name = "${var.name}-stage-runner", namespace = local.namespace, labels = local.labels }, roleRef = { apiGroup = "rbac.authorization.k8s.io", kind = "Role", name = "${var.name}-stage-runner" }, subjects = [{ kind = "User", name = oci_devops_deploy_pipeline.stage[0].id, apiGroup = "rbac.authorization.k8s.io" }] },
      { apiVersion = "rbac.authorization.k8s.io/v1", kind = "ClusterRole", metadata = { name = "${var.name}-${local.owner}-cpu-reader", labels = local.labels }, rules = [
        { apiGroups = [""], resources = ["nodes"], verbs = ["get", "list"] },
        { apiGroups = ["storage.k8s.io"], resources = ["storageclasses"], resourceNames = [var.storage_class], verbs = ["get"] }
      ] },
      { apiVersion = "rbac.authorization.k8s.io/v1", kind = "ClusterRoleBinding", metadata = { name = "${var.name}-${local.owner}-cpu-reader", labels = local.labels }, roleRef = { apiGroup = "rbac.authorization.k8s.io", kind = "ClusterRole", name = "${var.name}-${local.owner}-cpu-reader" }, subjects = [{ kind = "User", name = oci_devops_deploy_pipeline.stage[0].id, apiGroup = "rbac.authorization.k8s.io" }] }
    ]
  } : null
}
output "bootstrap_manifest" { value = local.bootstrap_manifest }
output "command_spec" { value = local.command_spec }
output "all_pipeline_ids" { value = [for pipeline in oci_devops_deploy_pipeline.stage : pipeline.id] }
output "storage" {
  value = {
    mode                         = var.mode, bucket_name = try(oci_objectstorage_bucket.weights[0].name, null),
    storage_namespace            = try(data.oci_objectstorage_namespace.model[0].namespace, null),
    prefix                       = local.enabled ? local.prefix : null, manifest_key = local.enabled ? "${local.prefix}/manifest.json" : null,
    snapshot_sha256              = local.enabled ? local.snapshot : null, pipeline_id = try(oci_devops_deploy_pipeline.stage[0].id, null),
    namespace                    = local.enabled ? local.namespace : null, service_account = local.enabled ? var.service_account : null,
    scratch_pvc                  = local.enabled ? local.pvc_name : null,
    runtime_status               = local.enabled ? "requires_validation" : "not_applicable",
    model_deployment_integration = "pending: model stack must materialize and verify the snapshot into a local/PVC model path before vLLM starts",
    retained                     = local.enabled
  }
}
