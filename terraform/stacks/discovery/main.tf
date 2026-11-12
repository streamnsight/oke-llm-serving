# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# The CLI helper maps RMS delegated auth; local runs use the OCI CLI config/profile.
data "external" "oci_discovery" {
  program = ["bash", "${path.module}/../../../scripts/discover-oci.sh"]
  query = {
    tenancy_ocid                = var.tenancy_ocid
    compartment_id              = coalesce(var.compartment_id, var.tenancy_ocid)
    region                      = var.region == null ? "" : var.region
    regions                     = jsonencode(sort(tolist(var.regions)))
    shape_names                 = jsonencode(sort(tolist(var.shape_names)))
    query_resource_availability = tostring(var.query_resource_availability)
    only_shapes_with_limits     = tostring(var.only_shapes_with_limits)
    observation_id              = var.observation_id
    gpu_catalog                 = file("${path.module}/../../../catalogs/gpus.json")
  }
}

locals {
  model_catalog      = jsondecode(file("${path.module}/../../../catalogs/models.json"))
  catalog_choice     = try([for model in local.model_catalog.models : model if model.id == var.model_choice][0], null)
  explicit_model     = try(length(trimspace(var.model)) > 0, false)
  effective_model    = local.explicit_model ? trimspace(var.model) : try(local.catalog_choice.id, "")
  effective_revision = local.explicit_model ? var.revision : coalesce(try(local.catalog_choice.sha, null), var.revision)
  oci_discovery      = jsondecode(data.external.oci_discovery.result.result)
  subscribed_regions = toset(local.oci_discovery.subscribed_regions)
  selected_regions   = toset(local.oci_discovery.assessed_regions)
  regional_results   = local.oci_discovery.regions
}

module "model_profile" {
  source         = "../../modules/model-profile"
  model          = local.effective_model
  revision       = local.effective_revision
  context_length = var.context_length
  concurrency    = var.concurrency
}

module "serving_resolution" {
  source              = "../../modules/serving-resolution"
  profile             = module.model_profile.profile
  assess_alternatives = true
}

locals {
  discovery_result = {
    schema_version        = "1.0"
    observation_id        = var.observation_id
    profile               = module.model_profile.profile
    serving_configuration = module.serving_resolution.resolution
    assessment            = module.planner.assessment
    home_region           = try(local.oci_discovery.home_region, null)
    subscribed_regions    = sort(tolist(local.subscribed_regions))
    assessed_regions      = sort(tolist(local.selected_regions))
    regions               = local.regional_results
    next_step             = "Pass deployment_inputs JSON to the deployment stack; select an assessment choice and target infrastructure there. Image, feature and expert overrides are deployment inputs."
  }

}

output "discovery" { value = local.discovery_result }
output "deployment_inputs" {
  description = "Single JSON handoff: use directly as deployment tfvars, or paste the object in the deployment discovery input."
  value = { discovery = {
    schema_version        = "2.0", observation_id = var.observation_id, profile = module.model_profile.profile,
    serving_configuration = module.serving_resolution.resolution,
    assessment = {
      recommended_selection_id       = try(module.planner.assessment.recommended_selection_id, null)
      suggestions                    = try(module.planner.assessment.suggestions, [])
      recipe_options                 = try(module.planner.assessment.recipe_options, {})
      recipe_alternatives            = try(module.planner.assessment.recipe_alternatives, {})
      sizing_diagnostics             = try(module.planner.assessment.sizing_diagnostics, [])
      availability_diagnostics       = try(module.planner.assessment.shape_observations, [])
      recipe_api_diagnostics         = try(module.planner.assessment.recipe_api_diagnostics, {})
      status                         = try(module.planner.assessment.status, "requires_validation"),
      blocking_reasons               = try(module.planner.assessment.blocking_reasons, []),
      warnings                       = try(module.planner.assessment.warnings, []),
      limit_increase_recommendations = try(module.planner.assessment.limit_increase_recommendations, []),
      candidates                     = [for c in try(module.planner.assessment.candidates, []) : { for k, v in c : k => v if !contains(["engine", "remaining_checks"], k) }],
      sizing_options                 = [for c in try(module.planner.assessment.sizing_options, []) : { for k, v in c : k => v if !contains(["engine", "remaining_checks"], k) }],
      recipe_hardware_targets        = [for t in try(module.planner.assessment.recipe_hardware_targets, []) : { for k, v in t : k => v if k != "observations" }]
    }
  } }
}

module "planner" {
  source             = "../../modules/deployment-planner"
  recipe_api_enabled = true
  profile            = module.model_profile.profile
  regions            = local.regional_results
  engines            = try(module.serving_resolution.resolution.engine.image != null && length(module.serving_resolution.resolution.engine_issues) == 0, false) ? [module.serving_resolution.resolution.engine] : []
  serving_resolution = module.serving_resolution.resolution
}

output "assessment" {
  value = module.planner.assessment
}

output "recommendations" {
  description = "Readable GPU/region choices. Pass deployment_inputs unchanged and select one ID in deployment."
  value = {
    recommended_selection_id = try(module.planner.assessment.recommended_selection_id, null)
    ranking                  = "Only capacity/headroom-confirmed options; fewer allocated host GPUs, then smaller TP. No cost/throughput prediction."
    choices = [for s in try(module.planner.assessment.suggestions, []) : {
      id           = s.id, region = s.region, availability_domain = s.availability_domain, gpu_shape = s.gpu_shape,
      node_count   = s.node_count, tensor_parallel_size = s.tensor_parallel_size, pipeline_parallel_size = s.pipeline_parallel_size,
      availability = s.availability, configuration_origin = s.configuration_origin, runtime_validation = s.runtime_validation,
      image        = s.serving_configuration.engine.image, warnings = s.warnings, deployment_requirements = try(s.deployment_requirements, [])
    }]
  }
}
