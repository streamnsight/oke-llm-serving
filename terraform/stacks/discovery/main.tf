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

# The Go SDK lookup uses resource-principal credentials in RMS, DEFAULT locally.
data "external" "oci_discovery" {
  program = ["bash", "${path.module}/../../../scripts/run-discovery-sdk.sh"]
  query = {
    tenancy_ocid                = var.tenancy_ocid
    compartment_id              = coalesce(var.compartment_id, var.tenancy_ocid)
    region                      = var.region
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
  kv_dtype       = var.kv_dtype
  runtime_gib    = var.runtime_gib
  margin         = var.margin
}

output "discovery" {
  value = {
    schema_version     = "1.0"
    observation_id     = var.observation_id
    profile            = module.model_profile.profile
    assessment         = module.planner.assessment
    subscribed_regions = sort(tolist(local.subscribed_regions))
    assessed_regions   = sort(tolist(local.selected_regions))
    regions            = local.regional_results
    next_step          = "Select region, AD, OKE cluster, shape and node quantity after per-rank VRAM/topology assessment; pass pinned model revision and serving settings to the deployment stack."
  }

}

module "planner" {
  source  = "../../modules/deployment-planner"
  profile = module.model_profile.profile
  regions = local.regional_results
}

output "assessment" {
  value = module.planner.assessment
}
