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
  count              = 1
  source             = "./modules/discovery/infrastructure-publisher"
  tenancy_ocid       = var.tenancy_ocid
  compartment_id     = coalesce(var.artifact_compartment_id, var.compartment_ocid, var.compartment_id, var.tenancy_ocid)
  region             = try(coalesce(var.region, local.oci_discovery.home_region), null)
  template_dir       = "${path.module}/templates/infrastructure"
  modules_dir        = "${path.module}/modules"
  options            = { for id, option in local.infrastructure_options : id => option if var.publish_infrastructure_bundles }
  par_lifetime_hours = var.par_lifetime_hours
  model = {
    repository                = try(module.model_profile.profile.model.repository, local.effective_model),
    revision                  = try(module.model_profile.profile.model.resolved_revision, null),
    checkpoint_download_bytes = try(module.model_profile.profile.weights.checkpoint_download_bytes, null),
    staging_files             = try(module.model_profile.profile.weights.staging_files, []),
    context_length            = var.context_length, concurrency = var.concurrency
  }
}
locals {
  published_options     = try(module.infrastructure_publication[0].deployment_options, {})
  publication_location  = try(module.infrastructure_publication[0].artifact_location, null)
  comparison_report_url = try(oci_objectstorage_preauthrequest.comparison[0].full_path, null)
  report_model_folder   = replace(replace(try(module.model_profile.profile.model.repository, local.effective_model), "/", "--"), "/[^A-Za-z0-9_.-]/", "-")
}
resource "oci_objectstorage_object" "comparison" {
  count               = 1
  namespace           = local.publication_location.namespace
  bucket              = local.publication_location.bucket
  object              = "models/${local.report_model_folder}/discovery-${formatdate("YYYYMMDD'T'hhmmss'Z'", local.publication_location.published_at)}-${substr(sha256(module.discovery_report.html), 0, 20)}.html"
  content             = module.discovery_report.html
  content_type        = "text/html; charset=utf-8"
  content_disposition = "inline"
}
resource "oci_objectstorage_preauthrequest" "comparison" {
  count        = 1
  namespace    = local.publication_location.namespace
  bucket       = local.publication_location.bucket
  object_name  = oci_objectstorage_object.comparison[0].object
  name         = "discovery-comparison"
  access_type  = "ObjectRead"
  time_expires = timeadd(local.publication_location.published_at, "${var.par_lifetime_hours}h")
}
output "comparison_report_url" {
  description = "Open the complete model, memory, deployment options and regional capacity report. The link expires with its PAR."
  value       = local.comparison_report_url
}
