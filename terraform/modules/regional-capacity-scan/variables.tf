# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "tenancy_ocid" {
  description = "Root tenancy for shape visibility and capacity reports."
  type        = string
}
variable "region" {
  description = "Must match the passed OCI provider region."
  type        = string
}
variable "observation_id" {
  description = "Run identifier; a changed value deliberately creates fresh reports."
  type        = string
}
variable "shape_names" {
  description = "Empty checks all GPU shapes listed by OCI in each AD."
  type        = set(string)
  default     = []
}
variable "assess_capacity" {
  description = "False only enumerates subscriptions/ADs/shapes without creating reports."
  type        = bool
  default     = true
}
variable "compartment_id" {
  description = "Optional intended deployment compartment for entitlement checks; capacity still uses root."
  type        = string
  default     = null
}
variable "query_resource_availability" {
  description = "Query headroom only for supported limit definitions. API errors fail the job."
  type        = bool
  default     = true
}

variable "only_shapes_with_limits" {
  description = "Skip confirmed zero-limit shapes/headroom queries; retain unknown quota mappings. False scans all visible GPU shapes."
  type        = bool
  default     = false
}
