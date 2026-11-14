# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  staging_cpu_shape = try(coalesce(var.model_staging_cpu_shape, try(module.target.target.cpu_shapes[0], null)), null)
  staging_model = local.selected_specification == null ? null : {
    id      = local.selected_specification.model.repository, revision = local.selected_specification.model.revision,
    variant = "selected-snapshot", files = try(local.selected_specification.model.staging_files, [])
  }
}
module "model_storage" {
  providers              = { oci = oci, oci.home = oci.home }
  source                 = "../../modules/model-storage"
  mode                   = var.model_storage_mode
  name                   = "${substr(var.platform_name, 0, 24)}-model"
  tenancy_ocid           = var.tenancy_ocid
  compartment_id         = local.compartment_id
  project_id             = module.bootstrap.platform.project_id
  artifact_repository_id = module.bootstrap.platform.script_repository_id
  result_repository_id   = module.bootstrap.platform.result_repository_id
  cluster_id             = var.cluster_id
  cluster_compartment_id = module.target.target.cluster_compartment_id
  cluster_type           = try(module.target.target.cluster_type, null)
  region                 = var.region
  kubernetes_version     = module.target.target.kubernetes_version
  subnet_id              = module.target.target.devops_subnet_id
  nsg_ids                = module.target.target.devops_nsg_ids
  model                  = var.model_storage_mode == "object_storage" ? local.staging_model : null
  staging_image          = var.model_staging_image
  cpu_node_selector      = local.staging_cpu_shape == null ? {} : { "node.kubernetes.io/instance-type" = local.staging_cpu_shape }
  scratch_gib            = local.staging_model == null ? 64 : max(64, ceil(max(concat([0], [for f in local.staging_model.files : coalesce(f.size_bytes, 0)])...) * 1.1 / pow(1024, 3)) + 1)
}
output "model_storage" {
  description = "Optional retained model data and download pipeline. Direct Hub mode creates neither. No model is served by this stack."
  value       = module.model_storage.storage
}
output "model_staging_bootstrap" {
  description = "Review/apply the owned namespace, CPU scratch PVC and workload-identity service account before running optional staging."
  value       = module.model_storage.bootstrap_manifest
}
