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

data "oci_identity_availability_domains" "domains" {
  count          = var.availability_domain == null ? 1 : 0
  compartment_id = var.tenancy_ocid
}

data "oci_core_shapes" "domain" {
  for_each            = var.availability_domain == null ? toset(data.oci_identity_availability_domains.domains[0].availability_domains[*].name) : toset([var.availability_domain])
  compartment_id      = coalesce(var.compartment_id, var.tenancy_ocid)
  availability_domain = each.key
  image_id            = var.image_id
}

data "oci_limits_limit_definitions" "compute" {
  compartment_id = var.tenancy_ocid
  service_name   = "compute"
}

data "oci_limits_limit_values" "compute" {
  compartment_id = var.tenancy_ocid
  service_name   = "compute"
}

locals {
  gpu_catalog = jsondecode(file("${path.module}/data/gpus.json"))
  definitions = { for definition in data.oci_limits_limit_definitions.compute.limit_definitions : definition.name => definition }
  shapes_by_ad = {
    for ad, listing in data.oci_core_shapes.domain : ad => [
      for shape in listing.shapes : {
        shape                         = shape.name
        gpus                          = shape.gpus
        gpu_description               = shape.gpu_description
        host_memory_gb                = shape.memory_in_gbs
        ocpus                         = shape.ocpus
        local_disks_total_size_in_gbs = shape.local_disks_total_size_in_gbs
        rdma_ports                    = shape.rdma_ports
        rdma_bandwidth_in_gbps        = shape.rdma_bandwidth_in_gbps
        quota_names                   = shape.quota_names == null ? [] : shape.quota_names
        gpu_memory_gib                = try(local.gpu_catalog.shapes[shape.name].memory_bytes_per_gpu / pow(1024, 3), null)
        gpu_memory_bytes_per_gpu      = try(local.gpu_catalog.shapes[shape.name].memory_bytes_per_gpu, null)
        gpu_memory_source             = try(local.gpu_catalog.shapes[shape.name].memory_bytes_per_gpu > 0, false) ? try(local.gpu_catalog.shape_sources[shape.name], local.gpu_catalog.source) : null
        nvlink_topology               = null
      } if coalesce(shape.gpus, 0) > 0 && (length(var.shape_names) == 0 || contains(var.shape_names, shape.name))
    ]
  }
  quota_names = toset(flatten([for shapes in values(local.shapes_by_ad) : flatten([for shape in shapes : shape.quota_names])]))
  limits = {
    for limit in data.oci_limits_limit_values.compute.limit_values : jsonencode([limit.name, limit.scope_type, limit.availability_domain]) => limit
    if contains(local.quota_names, limit.name) &&
    (var.availability_domain == null || limit.scope_type != "AD" || limit.availability_domain == var.availability_domain)
  }
  eligible_limits = {
    for key, limit in local.limits : key => limit
    if var.query_resource_availability && !contains(var.exclude_limit_names, limit.name) &&
    (!var.only_shapes_with_limits || (contains(local.quota_names, limit.name) && try(tonumber(limit.value) > 0, true))) &&
    try(local.definitions[limit.name].is_resource_availability_supported == true, false) &&
    contains(["AD", "REGION", "GLOBAL"], limit.scope_type) &&
    (limit.scope_type != "AD" || try(length(limit.availability_domain) > 0, false))
  }
  ordered_keys         = sort(keys(local.eligible_limits))
  selected_keys        = toset(slice(local.ordered_keys, 0, min(var.max_limit_checks, length(local.eligible_limits))))
  unmapped_quota_names = setsubtract(local.quota_names, toset([for limit in values(local.limits) : limit.name]))
}

data "oci_limits_resource_availability" "headroom" {
  for_each            = { for key, limit in local.eligible_limits : key => limit if contains(local.selected_keys, key) }
  compartment_id      = coalesce(var.compartment_id, var.tenancy_ocid)
  service_name        = "compute"
  limit_name          = each.value.name
  availability_domain = each.value.scope_type == "AD" ? each.value.availability_domain : null
}

locals {
  limit_observations = [for key, limit in local.limits : {
    name                     = limit.name
    scope_type               = limit.scope_type
    availability_domain      = limit.availability_domain
    tenancy_limit            = limit.value
    matched_shape_quota_name = contains(local.quota_names, limit.name)
    description              = try(local.definitions[limit.name].description, null)
    resource_availability = contains(local.selected_keys, key) ? {
      status                  = try(data.oci_limits_resource_availability.headroom[key].available != null || data.oci_limits_resource_availability.headroom[key].fractional_availability != null, false) ? "observed" : "unknown"
      reason                  = null
      available               = data.oci_limits_resource_availability.headroom[key].available
      used                    = data.oci_limits_resource_availability.headroom[key].used
      fractional_availability = data.oci_limits_resource_availability.headroom[key].fractional_availability
      fractional_usage        = data.oci_limits_resource_availability.headroom[key].fractional_usage
      effective_quota_value   = data.oci_limits_resource_availability.headroom[key].effective_quota_value
      } : {
      status    = "unknown"
      reason    = !var.query_resource_availability ? "Headroom queries disabled." : contains(var.exclude_limit_names, limit.name) ? "Limit explicitly excluded." : var.only_shapes_with_limits && (!contains(local.quota_names, limit.name) || try(tonumber(limit.value) == 0, false)) ? "Skipped by only_shapes_with_limits." : !contains(keys(local.eligible_limits), key) ? "Availability unsupported or scope unresolved." : "Query budget exhausted."
      available = null, used = null, fractional_availability = null, fractional_usage = null, effective_quota_value = null
    }
  }]
}

output "result" {
  description = "Regional shape and entitlement observations from native OCI data sources; API errors fail the plan."
  value = {
    schema_version = "2.0"
    region         = var.region
    tenancy_id     = var.tenancy_ocid
    compartment_id = coalesce(var.compartment_id, var.tenancy_ocid)
    status         = length(local.unmapped_quota_names) == 0 && alltrue([for limit in local.limit_observations : limit.resource_availability.status == "observed"]) ? "complete" : "partial"
    availability_domains = [for ad, shapes in local.shapes_by_ad : {
      name = ad, shapes = shapes
    }]
    limits                     = local.limit_observations
    unmapped_shape_quota_names = local.unmapped_quota_names
    headroom_queries_used      = length(local.selected_keys)
    warnings = [
      "Shapes, quota headroom and physical capacity are separate observations.",
      "Host memory is not GPU VRAM; topology catalog enrichment is still required.",
      "The supplied region label must match the inherited OCI provider region.",
    ]
  }
}
