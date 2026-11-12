# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  # These observations do not depend on model/engine compatibility.
  quota_observations = [for row in local.shape_rows : merge(row, {
    mapping_complete = length(row.shape.quota_names) > 0 && alltrue([
      for name in row.shape.quota_names : contains([for limit in row.headroom : limit.name], name)
    ])
    limit_status = anytrue([for limit in row.headroom : try(tonumber(limit.tenancy_limit) == 0, false)]) ? "zero" : (
      length(row.shape.quota_names) > 0 && alltrue([
        for name in row.shape.quota_names : anytrue([for limit in row.headroom : try(tonumber(limit.tenancy_limit) > 0, false) if limit.name == name])
      ]) ? "positive" : "unknown"
    )
    headroom_status = anytrue([for limit in row.headroom : try(limit.resource_availability.status == "observed" && coalesce(try(tonumber(limit.resource_availability.fractional_availability), null), try(tonumber(limit.resource_availability.available), null)) <= 0, false)]) ? "zero" : (
      length(row.headroom) > 0 && alltrue([for limit in row.headroom : try(limit.resource_availability.status == "observed" && coalesce(try(tonumber(limit.resource_availability.fractional_availability), null), try(tonumber(limit.resource_availability.available), null)) > 0, false)]) ? "positive" : "unknown"
    )
    capacity_status = try(row.capacity.availability_status == "AVAILABLE" && row.capacity.available_instances > 0, false) ? "positive" : (
      try(row.capacity.availability_status == "OUT_OF_HOST_CAPACITY" || (row.capacity.availability_status == "AVAILABLE" && row.capacity.available_instances == 0), false) ? "zero" : "unknown"
    )
  })]
  # Use the same explicit GPU-unit evidence required by allocation admission.
  # Positive headroom alone does not establish enough quota for a whole host.
  quantity_observations = [for row in local.quota_observations : merge(row, {
    entitled_instances = try(row.mapping_complete && alltrue([for limit in row.headroom : startswith(limit.description, "GPUs for ") && limit.resource_availability.status == "observed"]) ? floor(min([for limit in row.headroom : coalesce(try(tonumber(limit.resource_availability.fractional_availability), null), try(tonumber(limit.resource_availability.available), null))]...) / row.shape.gpus) : null, null)
  })]
  availability_observations = [for row in local.quantity_observations : {
    region                 = row.region
    availability_domain    = row.ad
    shape                  = row.shape.shape
    capacity               = row.capacity
    capacity_status        = row.capacity_status
    limit_status           = row.limit_status
    headroom_status        = row.mapping_complete ? row.headroom_status : "unknown"
    quota_mapping_complete = row.mapping_complete
    entitled_instances     = row.entitled_instances
    eligible_at_scan       = try(row.capacity_status == "positive" && row.capacity.available_instances >= var.replicas && row.limit_status == "positive" && row.entitled_instances >= var.replicas, false)
    exclusion_reasons = compact([
      row.capacity_status == "zero" ? "No physical capacity reported." : row.capacity_status != "positive" ? "No positive physical capacity report." : try(row.capacity.available_instances < var.replicas, true) ? "Insufficient physical instances for the requested replicas." : "",
      row.limit_status == "zero" ? "GPU limit is zero." : row.limit_status != "positive" ? "Applicable positive GPU limits are not confirmed." : "",
      row.entitled_instances == null ? "Quantity-specific GPU headroom or its units are not confirmed." : row.entitled_instances < var.replicas ? "GPU headroom cannot cover the requested complete shape instances." : ""
    ])
    limits = [for limit in row.headroom : {
      name                  = limit.name
      scope_type            = limit.scope_type
      availability_domain   = limit.availability_domain
      tenancy_limit         = try(limit.tenancy_limit, null)
      resource_availability = limit.resource_availability
    }]
    status = row.capacity_status == "zero" ? "no_capacity" : row.capacity_status != "positive" ? "unknown" : (
      row.limit_status == "zero" ? "limit_increase_required" : row.headroom_status == "zero" ? "headroom_exhausted" : (
        row.mapping_complete && row.limit_status == "positive" && row.headroom_status == "positive" ? "capacity_and_headroom" : "unknown"
      )
    )
  }]
  capacity_and_headroom_shapes = [for row in local.availability_observations : row if row.status == "capacity_and_headroom"]
  limit_increase_recommendations = flatten([
    for row in local.availability_observations : [for limit in row.limits : {
      region              = row.region
      availability_domain = row.availability_domain
      shape               = row.shape
      limit_name          = limit.name
      scope_type          = limit.scope_type
      current_limit       = limit.tenancy_limit
      recommendation      = "Request an increase for ${limit.name} in ${row.region}${limit.scope_type == "AD" ? " / ${row.availability_domain}" : ""} to use ${row.shape}; physical capacity was observed. Confirm quota units and the required instance quantity before requesting."
    } if try(tonumber(limit.tenancy_limit) == 0, false)]
    if length(local.capacity_and_headroom_shapes) == 0 && row.status == "limit_increase_required"
  ])
}
