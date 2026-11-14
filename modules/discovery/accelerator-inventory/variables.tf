# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "tenancy_ocid" {
  description = "Root tenancy OCID for ADs and service-limit metadata."
  type        = string
  nullable    = false
}
variable "region" {
  description = "Region label; must match the OCI provider passed by the caller. One module instance scans one provider region."
  type        = string
  nullable    = false
}
variable "compartment_id" {
  description = "Target compartment for shapes and entitlement headroom; null selects the root tenancy."
  type        = string
  default     = null
}
variable "availability_domain" {
  description = "Optional selected AD for allocation admission. Null inventories all ADs in the provider region."
  type        = string
  default     = null
  validation {
    condition     = var.availability_domain == null ? true : trimspace(var.availability_domain) != ""
    error_message = "Use an AD name or null for all ADs."
  }
}
variable "image_id" {
  description = "Optional image OCID to filter compatible shapes in this region."
  type        = string
  default     = null
}
variable "shape_names" {
  description = "Selected GPU shapes; empty retains every visible GPU shape."
  type        = set(string)
  default     = []
}
variable "query_resource_availability" {
  description = "Whether to query headroom for limits whose metadata explicitly supports the API."
  type        = bool
  default     = true
}
variable "exclude_limit_names" {
  description = "Explicitly omit problematic limit APIs; omitted headroom remains unknown."
  type        = set(string)
  default     = []
}
variable "max_limit_checks" {
  description = "Maximum deterministic headroom queries in this region."
  type        = number
  default     = 1000
  validation {
    condition     = var.max_limit_checks >= 0 && var.max_limit_checks <= 1000 && floor(var.max_limit_checks) == var.max_limit_checks
    error_message = "Use an integer between 0 and 1000."
  }
}

variable "only_shapes_with_limits" {
  description = "Skip confirmed zero-limit shapes/headroom queries; retain unknown quota mappings. False scans all visible GPU shapes."
  type        = bool
  default     = false
}
