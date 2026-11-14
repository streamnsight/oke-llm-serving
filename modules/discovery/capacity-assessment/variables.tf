# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "tenancy_ocid" {
  description = "Root tenancy OCID. Capacity reports do not use a target deployment compartment."
  type        = string
  nullable    = false
}
variable "region" {
  description = "Region label matching the inherited OCI provider."
  type        = string
  nullable    = false
}
variable "availability_domain" {
  description = "Full tenancy-specific AD name in the provider's region."
  type        = string
  nullable    = false
}
variable "shape_names" {
  description = "Explicit shapes for the report."
  type        = set(string)
  validation {
    condition     = length(var.shape_names) > 0 && length(var.shape_names) <= 100 && alltrue([for shape in var.shape_names : length(trimspace(shape)) > 0])
    error_message = "Supply between 1 and 100 nonempty shape names."
  }
}
variable "observation_id" {
  description = "Change this run identifier to create a fresh report. Keep fixed for reproducible re-applies of a snapshot."
  type        = string
  validation {
    condition     = length(trimspace(var.observation_id)) > 0
    error_message = "An explicit nonempty observation_id is required."
  }
}
variable "fault_domain" {
  description = "Optional report scope; not an OKE compute-cluster placement setting."
  type        = string
  default     = null
}
variable "requested_instances" {
  description = "Instance count to compare per shape/FD row; not a GPU count."
  type        = number
  default     = 1
  validation {
    condition     = var.requested_instances > 0 && floor(var.requested_instances) == var.requested_instances
    error_message = "requested_instances must be a positive integer."
  }
}
