# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    archive  = { source = "hashicorp/archive", version = "~> 2.8" }
    oci      = { source = "oracle/oci", version = "~> 9.12" }
    external = { source = "hashicorp/external", version = "~> 2.3" }
    http     = { source = "hashicorp/http", version = "~> 3.4" }
  }
}
locals {
  # RMS list controls can submit blank rows rather than an empty collection.
  region_scope = sort(distinct(compact([for name in var.regions : try(trimspace(name), "")])))
  shape_scope  = sort(distinct(compact([for name in var.shape_names : try(trimspace(name), "")])))
  discovery_query = {
    tenancy_ocid            = var.tenancy_ocid, compartment_id = coalesce(var.compartment_id, var.tenancy_ocid),
    region                  = var.region == null ? "" : var.region, regions = jsonencode(local.region_scope),
    shape_names             = jsonencode(local.shape_scope), query_resource_availability = tostring(var.query_resource_availability),
    only_shapes_with_limits = tostring(var.only_shapes_with_limits), observation_id = var.observation_id
  }
}
module "oci_discovery" {
  source = "./modules/discovery/oci-discovery"
  query  = local.discovery_query
}
locals {
  effective_model    = trimspace(var.model)
  effective_revision = var.revision
  oci_discovery      = module.oci_discovery.result
  subscribed_regions = toset(local.oci_discovery.subscribed_regions)
  selected_regions   = toset(local.oci_discovery.assessed_regions)
  regional_results   = local.oci_discovery.regions
}
module "model_profile" {
  source          = "./modules/discovery/model-profile"
  model           = local.effective_model
  revision        = local.effective_revision
  context_length  = var.context_length
  concurrency     = var.concurrency
  recipe_metadata = local.recipe_metadata_snapshot
}
module "serving_resolution" {
  source              = "./modules/discovery/serving-resolution"
  profile             = module.model_profile.profile
  assess_alternatives = false
  recipe_metadata     = local.recipe_metadata_snapshot
}
module "planner" {
  source                    = "./modules/discovery/deployment-planner"
  recipe_api_enabled        = true
  assess_cache_alternatives = false
  profile                   = module.model_profile.profile
  regions                   = local.regional_results
  engines                   = try(module.serving_resolution.resolution.engine.image != null && length(module.serving_resolution.resolution.engine_issues) == 0, false) ? [module.serving_resolution.resolution.engine] : []
  serving_resolution        = module.serving_resolution.resolution
  recipe_metadata           = local.recipe_metadata_snapshot
}
module "discovery_report" {
  source                = "./modules/discovery/discovery-report"
  profile               = module.model_profile.profile
  assessment            = module.planner.assessment
  regions               = local.regional_results
  options               = local.infrastructure_options
  publications          = local.published_options
  model_publications    = local.published_model_options
  publication           = { published_at = local.publication_location.published_at, expires_at = timeadd(local.publication_location.published_at, "${var.par_lifetime_hours}h"), bundles_enabled = var.publish_infrastructure_bundles }
  serving_configuration = module.serving_resolution.resolution
  include_diagnostics   = var.include_diagnostics
  scan = {
    observation_id     = var.observation_id, home_region = try(local.oci_discovery.home_region, null),
    subscribed_regions = sort(tolist(local.subscribed_regions)), assessed_regions = sort(tolist(local.selected_regions))
  }
}
