# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    archive = { source = "hashicorp/archive", version = "~> 2.8" }
    oci     = { source = "oracle/oci", version = "~> 9.12" }
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

# The discovery module owns its runtime CLI helper and authentication mapping.
locals {
  discovery_query = {
    tenancy_ocid                = var.tenancy_ocid
    compartment_id              = coalesce(var.compartment_id, var.tenancy_ocid)
    region                      = var.region == null ? "" : var.region
    regions                     = jsonencode(sort(tolist(var.regions)))
    shape_names                 = jsonencode(sort(tolist(var.shape_names)))
    query_resource_availability = tostring(var.query_resource_availability)
    only_shapes_with_limits     = tostring(var.only_shapes_with_limits)
    observation_id              = var.observation_id
  }
}
module "oci_discovery" {
  source = "./modules/oci-discovery"
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
  source         = "./modules/model-profile"
  model          = local.effective_model
  revision       = local.effective_revision
  context_length = var.context_length
  concurrency    = var.concurrency
}

module "serving_resolution" {
  source              = "./modules/serving-resolution"
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
    next_step             = "Apply discovery to publish confirmed infrastructure ZIPs; open a deployment_options launch URL, select an existing cluster and review its preview. Model deployment remains a separate pending phase."
  }

}

output "discovery" { value = local.discovery_result }
output "deployment_inputs" {
  description = "Full audit/local tfvars handoff. Too large for an RMS variable: use deployment_handoffs or authenticated Object Storage transport."
  value = { discovery = {
    schema_version        = "2.0", observation_id = var.observation_id, profile = module.model_profile.profile,
    control_plane         = module.control_plane.requirements,
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

module "control_plane" { source = "./modules/control-plane-sizing" }
module "handoff" {
  source                = "./modules/deployment-handoff"
  profile               = module.model_profile.profile
  assessment            = merge(module.planner.assessment, { control_plane = module.control_plane.requirements })
  serving_configuration = module.serving_resolution.resolution
  observation_id        = var.observation_id
}
output "deployment_handoffs" { value = module.handoff.handoffs }

module "planner" {
  source             = "./modules/deployment-planner"
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
  description = "Readable GPU/region choices; deployment_options contains configured infrastructure launch links after Apply."
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
