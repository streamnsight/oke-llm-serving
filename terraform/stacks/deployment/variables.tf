# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "tenancy_ocid" { type = string }
variable "compartment_id" { type = string }
variable "region" { type = string }
variable "cluster_id" { type = string }
variable "availability_domain" { type = string }
variable "subnet_id" { type = string }
variable "cpu_subnet_id" { type = string }
variable "devops_subnet_id" { type = string }
variable "gpu_image_id" { type = string }
variable "cpu_image_id" { type = string }
variable "gpu_shape" { type = string }
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.name))
    error_message = "Use a DNS-safe deployment name of 2–32 characters."
  }
}
variable "node_count" { type = number }
variable "requires_rdma" { type = bool }
variable "tensor_parallel_size" { type = number }
variable "pipeline_parallel_size" { type = number }
variable "replicas" { type = number }
variable "model" { type = string }
variable "model_revision" {
  type = string
  validation {
    condition     = can(regex("^[a-fA-F0-9]{40}$", var.model_revision))
    error_message = "Deploy an immutable model commit SHA."
  }
}
variable "engine_image" {
  type = string
  validation {
    condition     = can(regex("@sha256:[a-f0-9]{64}$", var.engine_image))
    error_message = "engine_image must be pinned by SHA256 digest."
  }
}
variable "engine_version" { type = string }
variable "context_length" {
  type = number
  validation {
    condition     = var.context_length >= 256 && floor(var.context_length) == var.context_length
    error_message = "Initial chat validation requires context_length >= 256."
  }
}
variable "concurrency" {
  type = number
  validation {
    condition     = var.concurrency >= 1 && var.concurrency <= 256 && floor(var.concurrency) == var.concurrency
    error_message = "Initial validation supports 1–256 concurrent requests."
  }
}
variable "kv_dtype" { type = string }
variable "observation_id" {
  description = "Change before an allocation attempt to obtain a fresh capacity snapshot."
  type        = string
}
variable "assessment_id" { type = string }
variable "cpu_node_count" {
  type    = number
  default = 1
}
variable "boot_volume_gib" {
  type    = number
  default = 200
}
variable "install_gpu_operator" {
  description = "Install only when this cluster does not already manage the NVIDIA device plugin/operator. OKE GPU image must provide drivers/toolkit."
  type        = bool
  default     = true
}
variable "benchmark_requests" {
  type    = number
  default = 50
  validation {
    condition     = var.benchmark_requests >= 1 && var.benchmark_requests <= 10000 && floor(var.benchmark_requests) == var.benchmark_requests
    error_message = "benchmark_requests must be an integer from 1 to 10000."
  }
}
variable "benchmark_output_tokens" {
  type    = number
  default = 128
  validation {
    condition     = var.benchmark_output_tokens >= 1 && floor(var.benchmark_output_tokens) == var.benchmark_output_tokens
    error_message = "benchmark_output_tokens must be a positive integer."
  }
}
variable "benchmark_input_tokens" {
  type    = number
  default = 1024
  validation {
    condition     = var.benchmark_input_tokens >= 1 && floor(var.benchmark_input_tokens) == var.benchmark_input_tokens
    error_message = "benchmark_input_tokens must be a positive integer."
  }
}
variable "pod_subnet_id" {
  type    = string
  default = null
}
variable "runtime_gib" {
  type    = number
  default = 2
}
variable "margin" {
  type    = number
  default = 0.2
}

variable "serving_configuration" {
  description = "Frozen discovery recipe/image evidence. Deployment does not re-resolve mutable upstream tags."
  type        = any
  default     = null
}
variable "expert_configuration" {
  description = "Explicitly deploy expert-supplied settings for an untested or undetermined configuration; runtime validation remains required."
  type        = bool
  default     = false
}
variable "expert_rank_memory_gib" {
  description = "Expert per-rank total GPU memory bound, including weights, KV and runtime. Required when the built-in estimator is unsupported."
  type        = number
  default     = null
  validation {
    condition     = var.expert_rank_memory_gib == null ? true : var.expert_rank_memory_gib > 0
    error_message = "An expert rank-memory bound must be positive."
  }
}
variable "engine_args" {
  description = "Optional explicit argv override for recipe arguments; identity/topology/memory are managed by dedicated variables."
  type        = list(string)
  default     = null
}
variable "engine_env" {
  description = "Optional explicit serving environment override, excluding credentials."
  type        = map(string)
  default     = null
}
