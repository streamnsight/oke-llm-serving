# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "model_spec" {
  description = "Frozen selected model/recipe/profile and complete assessment option; null disables publication."
  type        = any
  default     = null
}
variable "platform_binding" {
  description = "Existing platform IDs and allocation geometry. Debug bindings may have no GPU pool; runtime deployment must then fail preflight."
  type        = any
}
variable "publication" {
  description = "Original discovery ZIP bucket. Pass an OCI provider configured for its region; this module creates no buckets."
  type = object({
    namespace = string, bucket_name = string, region = string, par_lifetime_hours = optional(number, 24)
  })
  default = null
  validation {
    condition     = var.publication == null ? true : try(var.publication.par_lifetime_hours >= 1 && var.publication.par_lifetime_hours <= 168 && floor(var.publication.par_lifetime_hours) == var.publication.par_lifetime_hours, false)
    error_message = "Publication links expire after 1 to 168 whole hours."
  }
}
variable "template_dir" { type = string }
variable "modules_dir" { type = string }
