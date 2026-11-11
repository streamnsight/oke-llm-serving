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

# A changed observation ID deliberately creates a fresh report, not GPU instances.
resource "terraform_data" "observation" {
  triggers_replace = var.observation_id
}

resource "oci_core_compute_capacity_report" "report" {
  compartment_id      = var.tenancy_ocid
  availability_domain = var.availability_domain
  dynamic "shape_availabilities" {
    for_each = var.shape_names
    content {
      instance_shape = shape_availabilities.value
      fault_domain   = var.fault_domain
    }
  }
  lifecycle {
    replace_triggered_by = [terraform_data.observation]
  }
}

locals {
  rows = flatten([for shape in sort(tolist(var.shape_names)) : [
    for row in oci_core_compute_capacity_report.report.shape_availabilities : {
      shape               = shape
      fault_domain        = row.fault_domain
      availability_status = row.availability_status
      available_instances = try(tonumber(row.available_count), null)
      requested_instances = var.requested_instances
      reported_sufficient = row.availability_status == "OUT_OF_HOST_CAPACITY" ? false : row.availability_status == "AVAILABLE" && try(tonumber(row.available_count) >= 0, false) ? tonumber(row.available_count) >= var.requested_instances : null
    } if row.instance_shape == shape
  ]])
  missing_shapes = setsubtract(var.shape_names, toset([for row in local.rows : row.shape]))
}

output "result" {
  description = "Capacity report snapshot. Change observation_id for a new observation; refresh alone is not guaranteed to recreate it."
  value = {
    schema_version        = "2.0"
    region                = var.region
    availability_domain   = var.availability_domain
    fault_domain          = var.fault_domain
    report_compartment_id = var.tenancy_ocid
    observation_id        = var.observation_id
    observed_at           = oci_core_compute_capacity_report.report.time_created
    status                = length(local.missing_shapes) == 0 && alltrue([for row in local.rows : row.reported_sufficient != null]) ? "complete" : "partial"
    shapes                = local.rows
    missing_shapes        = local.missing_shapes
    warnings = [
      "This report is a snapshot, not a reservation or launch guarantee.",
      "Counts represent instances, not GPUs; fault-domain counts are never summed.",
      "Deployment-compartment entitlement and RDMA placement feasibility are not established by this report.",
    ]
  }
}
