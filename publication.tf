# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
provider "oci" { region = try(coalesce(var.region, local.oci_discovery.home_region), null) }
locals {
  infrastructure_options = merge(
    { for option in try(module.planner.assessment.candidates, []) : option.id => merge(option, { availability = "available_at_scan" }) },
    { for option in try(module.planner.assessment.suggestions, []) : option.id => option if try(option.availability == "available_at_scan", false) }
  )
}
module "infrastructure_publication" {
  count               = var.publish_infrastructure_bundles ? 1 : 0
  source              = "./modules/discovery/infrastructure-publisher"
  tenancy_ocid        = var.tenancy_ocid
  compartment_id      = coalesce(var.artifact_compartment_id, var.compartment_ocid, var.compartment_id, var.tenancy_ocid)
  region              = try(coalesce(var.region, local.oci_discovery.home_region), null)
  template_dir        = "${path.module}/templates/infrastructure"
  modules_dir         = "${path.module}/modules"
  options             = local.infrastructure_options
  par_lifetime_hours  = var.par_lifetime_hours
  skip_gpu_allocation = var.skip_gpu_allocation
  model = {
    repository                = try(module.model_profile.profile.model.repository, local.effective_model),
    revision                  = try(module.model_profile.profile.model.resolved_revision, null),
    checkpoint_download_bytes = try(module.model_profile.profile.weights.checkpoint_download_bytes, null),
    staging_files             = try(module.model_profile.profile.weights.staging_files, []),
    storage_mode              = var.model_storage_mode,
    context_length            = var.context_length, concurrency = var.concurrency
  }
}
output "deployment_options" {
  description = "Confirmed infrastructure ZIPs and region-specific RMS launch URLs. PARs grant read access to the ZIP until expiry or refresh."
  value       = try(module.infrastructure_publication[0].deployment_options, {})
}
output "recommended_launch_url" {
  description = "Open the recommended infrastructure stack in the selected region, then select an existing cluster and review preview."
  value       = try(module.infrastructure_publication[0].deployment_options[module.planner.assessment.recommended_selection_id].launch_url, null)
}
output "deployment_option_count" {
  description = "Number of confirmed infrastructure choices in deployment_options. The primary button opens only the recommendation."
  value       = length(try(module.infrastructure_publication[0].deployment_options, {}))
}
