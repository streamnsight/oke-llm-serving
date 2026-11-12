# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "tenancy_ocid" {
  description = "RMS tenancy root; used for capacity reports."
  type        = string
}
variable "region" {
  description = "RMS/bootstrap region for subscription lookup; not the deployment selection."
  type        = string
}
variable "model" {
  description = "Public Hugging Face repository URL or owner/model."
  type        = string
  default     = null
}
variable "model_choice" {
  description = "Legacy catalog selection for existing stacks. An explicit model URL/ID takes priority."
  type        = string
  default     = "custom"
}
variable "revision" {
  type    = string
  default = "main"
}
variable "context_length" {
  description = "Live tokens per sequence, including input and output."
  type        = number
  default     = 4096
}
variable "concurrency" {
  description = "Simultaneously active sequences at the specified context length."
  type        = number
  default     = 1
}
variable "kv_dtype" {
  type    = string
  default = "bfloat16"
}
variable "runtime_gib" {
  type    = number
  default = 2
}
variable "margin" {
  type    = number
  default = 0.2
}
variable "observation_id" {
  description = "Snapshot label. Discovery requests fresh reports whenever its data source is read."
  type        = string
  default     = "initial"
}
variable "regions" {
  description = "Empty selects every READY subscription. Optional subset for reruns/troubleshooting."
  type        = set(string)
  default     = []
  nullable    = false
}
variable "shape_names" {
  description = "Empty selects all visible GPU shapes."
  type        = set(string)
  default     = []
  nullable    = false
}
variable "compartment_id" {
  description = "Intended deployment compartment for quota headroom; null checks root entitlement only."
  type        = string
  default     = null
}
variable "query_resource_availability" {
  description = "Query supported compute limit headroom. Disable only for capacity-only investigation."
  type        = bool
  default     = true
}

variable "only_shapes_with_limits" {
  description = "Skip capacity checks for shapes with a confirmed zero limit. False also finds capacity that needs a limit increase. Unknown mappings remain included."
  type        = bool
  default     = false
}

variable "engine_channel" {
  type    = string
  default = "auto"
  validation {
    condition     = contains(["auto", "stable", "nightly"], var.engine_channel)
    error_message = "engine_channel must be auto, stable or nightly."
  }
}
variable "engine_version" {
  description = "Optional explicit stable X.Y.Z version. Null chooses the latest stable tag, with nightly fallback in auto mode."
  type        = string
  default     = null
  validation {
    condition     = var.engine_version == null ? true : trimspace(var.engine_version) == "" ? true : can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.engine_version))
    error_message = "Use an exact stable X.Y.Z engine_version, or engine_channel=nightly."
  }
}
variable "engine_platform" {
  type    = string
  default = "linux/amd64"
  validation {
    condition     = contains(["linux/amd64", "linux/arm64"], var.engine_platform)
    error_message = "Select linux/amd64 or linux/arm64."
  }
}
variable "recipe_features" {
  description = "Explicit optional recipe features such as reasoning and tool_calling."
  type        = set(string)
  default     = []
  nullable    = false
}
