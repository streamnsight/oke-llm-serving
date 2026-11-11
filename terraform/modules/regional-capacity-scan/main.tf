# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.12"
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
  # Inventory retains every visible shape. Only known zero limits suppress capacity calls.
  zero_limit_shapes_by_ad = {
    for ad in module.inventory.result.availability_domains : ad.name => toset([
      for shape in ad.shapes : shape.shape if anytrue([
        for limit in module.inventory.result.limits : try(tonumber(limit.tenancy_limit) == 0, false)
        if contains(shape.quota_names, limit.name) && (limit.scope_type != "AD" || limit.availability_domain == ad.name)
      ])
    ])
  }
  capacity_shapes_by_ad = {
    for ad, shapes in local.shapes_by_ad : ad => var.only_shapes_with_limits ? setsubtract(shapes, local.zero_limit_shapes_by_ad[ad]) : shapes
  }
}

module "capacity" {
  for_each            = { for ad, shapes in local.capacity_shapes_by_ad : ad => shapes if var.assess_capacity && length(shapes) > 0 }
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
      name                      = ad
      visible_gpu_shapes        = sort(tolist(shapes))
      assessed_gpu_shapes       = sort(tolist(local.capacity_shapes_by_ad[ad]))
      skipped_zero_limit_shapes = var.only_shapes_with_limits ? sort(tolist(local.zero_limit_shapes_by_ad[ad])) : []
      assessment                = try(module.capacity[ad].result, null)
      status                    = !var.assess_capacity ? "not_requested" : length(shapes) == 0 ? "no_gpu_shapes_listed" : length(local.capacity_shapes_by_ad[ad]) == 0 ? "skipped_zero_limits" : module.capacity[ad].result.status
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
  only_shapes_with_limits     = var.only_shapes_with_limits
}

output "inventory" {
  value = module.inventory.result
}
