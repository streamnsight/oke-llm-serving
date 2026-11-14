# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "profile" {
  description = "Native model-profile output; unknown estimates produce no memory-fit claims."
  type        = any
}
variable "regions" {
  description = "Regional discovery results, each containing inventory and capacity."
  type        = any
}
variable "engines" {
  description = "Engine evidence resolved live during discovery, or explicit caller-provided test/assessment evidence."
  type        = any
  default     = []
  nullable    = false
}
variable "gpu_catalog" {
  type    = any
  default = null
}
variable "max_nodes_per_replica" {
  type    = number
  default = 8
  validation {
    condition     = var.max_nodes_per_replica >= 1 && var.max_nodes_per_replica <= 32 && floor(var.max_nodes_per_replica) == var.max_nodes_per_replica
    error_message = "max_nodes_per_replica must be an integer from 1 to 32."
  }
}
variable "replicas" {
  description = "Minimum requested replicas; complete extra replicas fill spare GPUs on already allocated single-node hosts."
  type        = number
  default     = 1
  validation {
    condition     = var.replicas >= 1 && floor(var.replicas) == var.replicas
    error_message = "replicas must be a positive integer."
  }
}

variable "monitoring_enabled" {
  description = "Include monitoring requirements in each selected platform plan."
  type        = bool
  default     = true
}

variable "autoscaling_enabled" {
  description = "Opt into KEDA/Prometheus requirements; fixed replica packing does not require autoscaling."
  type        = bool
  default     = false
}

variable "serving_resolution" {
  description = "Frozen runtime recipe/image evidence. Analytical callers may omit recipe evidence; discovery supplies live resolved evidence."
  type        = any
  default     = null
}

variable "recipe_api_enabled" {
  description = "Resolve hardware-specific recipe JSON and generate untested single-node suggestions."
  type        = bool
  default     = false
}
