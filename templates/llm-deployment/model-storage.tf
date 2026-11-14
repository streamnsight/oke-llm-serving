# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  staging_cpu_shape = try(coalesce(var.model_staging_cpu_shape, try(one(module.target[0].target.cpu_shapes), null)), null)
  staging_model = local.configured ? {
    id      = local.model.model.repository, revision = local.model.model.revision,
    variant = "selected-snapshot", files = try(local.model.model.staging_files, [])
  } : null
}
module "model_storage" {
  count                  = local.configured ? 1 : 0
  providers              = { oci = oci, oci.home = oci.home }
  source                 = "../../modules/llm-deployment/model-storage"
  mode                   = var.storage_mode == "staged_object_storage" ? "object_storage" : "direct_huggingface"
  name                   = "weights-${substr(sha256("${var.cluster_id}/${local.model_namespace}"), 0, 24)}"
  namespace              = "${module.target[0].target.platform_name}-stage-${substr(sha256(local.model_namespace), 0, 10)}"
  tenancy_ocid           = var.tenancy_ocid
  compartment_id         = local.compartment_id
  project_id             = module.project[0].resources.project_id
  artifact_repository_id = module.project[0].resources.script_repository_id
  result_repository_id   = module.project[0].resources.result_repository_id
  cluster_id             = var.cluster_id
  cluster_compartment_id = module.target[0].target.cluster_compartment_id
  cluster_type           = module.target[0].target.cluster_type
  region                 = coalesce(var.region, local.expected_region)
  kubernetes_version     = module.target[0].target.kubernetes_version
  subnet_id              = module.target[0].target.runner_subnet_id
  nsg_ids                = module.target[0].target.runner_nsg_ids
  model                  = var.storage_mode == "staged_object_storage" ? local.staging_model : null
  staging_image          = var.model_staging_image
  cpu_node_selector      = local.staging_cpu_shape == null ? {} : { "node.kubernetes.io/instance-type" = local.staging_cpu_shape }
  scratch_gib            = local.staging_model == null ? 64 : max(64, ceil(max(concat([0], [for file in local.staging_model.files : coalesce(file.size_bytes, 0)])...) * 1.1 / pow(1024, 3)) + 1)
}
output "model_storage" {
  description = "Optional model-owned CPU staging and retained model data. Object Storage is not yet a mounted serving snapshot."
  value       = try(module.model_storage[0].storage, null)
}
output "model_staging_bootstrap" {
  description = "Explicit administrator bootstrap for the optional CPU staging namespace, workload identity, retained scratch PVC and scoped RBAC. No resources are automatically applied to Kubernetes."
  value       = try(module.model_storage[0].bootstrap_manifest, null)
}
