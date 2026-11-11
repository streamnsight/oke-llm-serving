terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}

data "oci_identity_region_subscriptions" "subscribed" {
  tenancy_id = var.tenancy_ocid
}

data "oci_identity_availability_domains" "domains" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_shapes" "domain" {
  for_each            = toset(data.oci_identity_availability_domains.domains.availability_domains[*].name)
  compartment_id      = var.tenancy_ocid
  availability_domain = each.key
}

locals {
  shapes_by_ad = {
    for ad, listing in data.oci_core_shapes.domain : ad => toset([
      for shape in listing.shapes : shape.name
      if coalesce(shape.gpus, 0) > 0 && (length(var.shape_names) == 0 || contains(var.shape_names, shape.name))
    ])
  }
}

module "capacity" {
  for_each            = { for ad, shapes in local.shapes_by_ad : ad => shapes if var.assess_capacity && length(shapes) > 0 }
  source              = "../capacity-assessment"
  tenancy_ocid        = var.tenancy_ocid
  region              = var.region
  availability_domain = each.key
  shape_names         = each.value
  observation_id      = var.observation_id
}

output "result" {
  value = {
    schema_version     = "1.0"
    region             = var.region
    subscriptions      = data.oci_identity_region_subscriptions.subscribed.region_subscriptions
    assessment_enabled = var.assess_capacity
    availability_domains = [for ad, shapes in local.shapes_by_ad : {
      name               = ad
      visible_gpu_shapes = sort(tolist(shapes))
      assessment         = try(module.capacity[ad].result, null)
      status             = !var.assess_capacity ? "not_requested" : length(shapes) == 0 ? "no_gpu_shapes_listed" : module.capacity[ad].result.status
    }]
  }
}

module "inventory" {
  source                      = "../accelerator-inventory"
  tenancy_ocid                = var.tenancy_ocid
  region                      = var.region
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  query_resource_availability = var.query_resource_availability
}

output "inventory" {
  value = module.inventory.result
}
