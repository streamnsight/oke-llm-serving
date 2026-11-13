# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "profile" { type = any }
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
variable "assess_alternatives" {
  description = "Include a supporting nightly image alternative as assessment evidence without requesting a deployment choice."
  type        = bool
  default     = false
}
