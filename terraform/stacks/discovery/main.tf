terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# RMS supplies authentication. Local runs use the DEFAULT profile.
provider "oci" {
  region = var.region
}

data "oci_identity_region_subscriptions" "subscribed" {
  tenancy_id = var.tenancy_ocid
}

locals {
  subscribed_regions = toset([for sub in data.oci_identity_region_subscriptions.subscribed.region_subscriptions : sub.region_name if sub.state == "READY"])
  requested_regions  = length(var.regions) == 0 ? local.subscribed_regions : var.regions
  selected_regions   = setintersection(local.requested_regions, local.subscribed_regions)
}

module "model_profile" {
  source         = "../../modules/model-profile"
  model          = var.model
  revision       = var.revision
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
    subscribed_regions = sort(tolist(local.subscribed_regions))
    assessed_regions   = sort(tolist(local.selected_regions))
    regions            = local.regional_results
    next_step          = "Select region, AD, OKE cluster, shape and node quantity after per-rank VRAM/topology assessment; pass pinned model revision and serving settings to the deployment stack."
  }
  precondition {
    condition     = length(setsubtract(local.requested_regions, local.subscribed_regions)) == 0
    error_message = "Requested regions must be READY subscriptions."
  }
  precondition {
    condition     = length(setsubtract(local.selected_regions, local.supported_regions)) == 0
    error_message = "A selected subscribed region has no checked-in provider alias. Update regions.tf before claiming complete coverage."
  }
  precondition {
    condition     = length(local.selected_regions) > 0
    error_message = "No READY subscribed regions selected."
  }
}
