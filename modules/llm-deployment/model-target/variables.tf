# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "cluster_id" { type = string }
variable "compartment_id" {
  type        = string
  default     = null
  description = "Model-project compartment included in the scoped trusted platform lookup; supplied by the stack."
}
variable "gpu_pool_id" {
  type    = string
  default = null
}
variable "gpu_pool_compartment_id" {
  type    = string
  default = null
}
variable "platform_name" {
  type    = string
  default = null
  validation {
    condition     = var.platform_name == null ? true : trimspace(var.platform_name) == "" ? true : can(regex("^[a-z][a-z0-9-]{0,39}$", var.platform_name))
    error_message = "platform_name must be a lowercase DNS label of at most 40 characters."
  }
}
variable "runner_subnet_id" {
  type    = string
  default = null
}
variable "runner_nsg_ids" {
  type    = list(string)
  default = null
}
variable "expected" {
  type = object({
    gpu_shape           = string
    availability_domain = string
    node_count          = number
    gpu_count_per_host  = number
  })
  description = "Frozen discovery geometry. This module reads metadata only; it never allocates GPUs, resolves images or changes pools."
}
