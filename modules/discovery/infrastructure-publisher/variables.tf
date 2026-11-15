# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "tenancy_ocid" { type = string }
variable "compartment_id" { type = string }
variable "region" { type = string }
variable "model" {
  description = "Selected model identity/revision and storage estimate; no credentials or full discovery report."
  type        = any
}
variable "options" {
  description = "Confirmed infrastructure choices keyed by assessment selection ID."
  type        = any
  default     = {}
  validation {
    condition     = alltrue([for id, option in var.options : can(regex("^[A-Za-z0-9_-]{1,64}$", id)) && try(option.availability == "available_at_scan" && option.node_count >= 1 && floor(option.node_count) == option.node_count, false)])
    error_message = "Publish only capacity/headroom-confirmed options with safe IDs and positive whole-host quantities."
  }
}
variable "template_dir" { type = string }
variable "modules_dir" { type = string }
variable "par_lifetime_hours" {
  type    = number
  default = 24
  validation {
    condition     = var.par_lifetime_hours >= 1 && var.par_lifetime_hours <= 168 && floor(var.par_lifetime_hours) == var.par_lifetime_hours
    error_message = "PAR lifetime must be 1–168 whole hours."
  }
}
