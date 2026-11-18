# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  # The model stack resolves cluster/pool IDs at launch, independently of any
  # infrastructure stack Apply. Reuse the existing discovery evidence and store.
  model_specifications = { for id, option in local.infrastructure_options : id => {
    schema_version = "2.0", kind = "llm_model", selection_id = id,
    model = {
      repository                = try(module.model_profile.profile.model.repository, local.effective_model),
      revision                  = try(module.model_profile.profile.model.resolved_revision, null),
      checkpoint_download_bytes = try(module.model_profile.profile.weights.checkpoint_download_bytes, null),
      staging_files             = try(module.model_profile.profile.weights.staging_files, []),
      context_length            = var.context_length, concurrency = var.concurrency, requested_replicas = var.replicas, routing_mode = var.routing_mode
    },
    profile               = module.model_profile.profile, selection = option,
    serving_configuration = try(option.serving_configuration, module.serving_resolution.resolution),
    source_commit         = try(jsondecode(file("${path.module}/package-manifest.json")).source_commit, null),
    publication_time      = local.publication_location.published_at
  } if var.publish_infrastructure_bundles }
}
module "model_publication" {
  for_each     = local.model_specifications
  source       = "./modules/discovery/model-publisher"
  model_spec   = each.value
  template_dir = "${path.module}/templates/llm-deployment"
  modules_dir  = "${path.module}/modules"
  publication = {
    namespace          = local.publication_location.namespace, bucket_name = local.publication_location.bucket,
    region             = local.publication_location.region, published_at = local.publication_location.published_at,
    par_lifetime_hours = var.par_lifetime_hours
  }
}
locals {
  published_model_options = { for id, publication in module.model_publication : id => publication.deployment }
}
