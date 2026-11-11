# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "model" {
  description = "Hugging Face owner/model or repository URL."
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", trimsuffix(trimprefix(var.model, "https://huggingface.co/"), "/")))
    error_message = "Use owner/model or https://huggingface.co/owner/model."
  }
}
variable "revision" {
  type    = string
  default = "main"
}
variable "context_length" {
  type    = number
  default = 4096
  validation {
    condition     = var.context_length > 0 && floor(var.context_length) == var.context_length
    error_message = "context_length must be a positive integer."
  }
}
variable "concurrency" {
  type    = number
  default = 1
  validation {
    condition     = var.concurrency > 0 && floor(var.concurrency) == var.concurrency
    error_message = "concurrency must be a positive integer."
  }
}
variable "kv_dtype" {
  type    = string
  default = "bfloat16"
  validation {
    condition     = contains(["bfloat16", "float16", "float32"], var.kv_dtype)
    error_message = "Use bfloat16, float16 or float32."
  }
}
variable "runtime_gib" {
  type    = number
  default = 2
  validation {
    condition     = var.runtime_gib >= 0
    error_message = "runtime_gib must be nonnegative."
  }
}
variable "margin" {
  type    = number
  default = 0.2
  validation {
    condition     = var.margin >= 0 && var.margin <= 1
    error_message = "margin must be between zero and one."
  }
}
