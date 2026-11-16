# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "tenancy_ocid" { type = string }
variable "compartment_id" { type = string }
variable "platform" {
  type        = any
  description = "Runtime target and independent model-project resources. Apply requires retained GPU infrastructure and trusted onboarding, then waits for model deployment and validation."
}
variable "model" {
  type        = any
  description = "Frozen llm_model specification, including the exact selection, recipe argv/env and profile."
}
variable "api_frontend" {
  type        = string
  default     = "python"
  description = "vLLM API frontend. Python is the default; Rust is an explicit opt-in requiring model/template compatibility validation."
  validation {
    condition     = contains(["python", "rust"], var.api_frontend)
    error_message = "api_frontend must be python or rust. Rust frontend support requires explicit compatibility validation."
  }
}
variable "name" {
  type     = string
  default  = null
  nullable = true
  validation {
    condition     = var.name == null ? true : can(regex("^[a-z][a-z0-9-]{0,29}$", var.name))
    error_message = "Model deployment name must be a lowercase DNS label of at most 30 characters."
  }
}
variable "namespace" {
  type     = string
  default  = null
  nullable = true
}
variable "overrides" {
  type = object({
    model_id               = optional(string)
    model_revision         = optional(string)
    serving_image          = optional(string)
    tensor_parallel_size   = optional(number)
    pipeline_parallel_size = optional(number)
    hosts_per_replica      = optional(number)
    gpus_per_pod           = optional(number)
    replicas               = optional(number)
    context_length         = optional(number)
    concurrency            = optional(number)
  })
  default = {}
}
variable "hf_token_secret" {
  type        = string
  default     = ""
  description = "Optional existing Secret with key token in the onboarded model namespace; never put token values in Terraform."
}
variable "storage" {
  type = object({
    mode          = optional(string, "direct_hf")
    pvc_name      = optional(string, "")
    model_path    = optional(string, "/models/model")
    workspace_gib = optional(number)
  })
  default = {}
  validation {
    condition     = contains(["direct_hf", "existing_pvc", "staged_object_storage"], var.storage.mode)
    error_message = "Storage mode must be direct_hf, existing_pvc or staged_object_storage. Staged content requires an existing materialized PVC."
  }
  validation {
    condition     = var.storage.workspace_gib == null ? true : var.storage.workspace_gib >= 1 && floor(var.storage.workspace_gib) == var.storage.workspace_gib
    error_message = "An explicit workspace must be a positive whole number of GiB per serving pod."
  }
}
variable "router_enabled" {
  type    = bool
  default = false
}
variable "autoscaling" {
  type = object({
    enabled         = optional(bool, false)
    min_replicas    = optional(number, 1)
    max_replicas    = optional(number, 1)
    prometheus_url  = optional(string, "")
    target_inflight = optional(number, 8)
  })
  default = {}
  validation {
    condition     = var.autoscaling.min_replicas >= 1 && var.autoscaling.max_replicas >= var.autoscaling.min_replicas && var.autoscaling.target_inflight >= 1 && alltrue([for value in [var.autoscaling.min_replicas, var.autoscaling.max_replicas, var.autoscaling.target_inflight] : floor(value) == value])
    error_message = "Autoscaling requires positive whole-number bounds/target, with maximum at least minimum."
  }
}
variable "inference_probe" {
  type    = string
  default = "none"
  validation {
    condition     = contains(["none", "completions", "chat"], var.inference_probe)
    error_message = "Use none for health/model identity only, or explicitly select a text completions/chat probe. Other modalities need a task-specific payload."
  }
}
variable "benchmark_backend" {
  type    = string
  default = "openai-chat"
  validation {
    condition     = contains(["unsupported", "openai", "openai-chat"], var.benchmark_backend)
    error_message = "Select an explicit supported benchmark backend; multimodal/audio tasks require a task-specific dataset adapter."
  }
}
variable "timeout_seconds" {
  type    = number
  default = 1800
  validation {
    condition     = var.timeout_seconds >= 300 && var.timeout_seconds <= 1800 && floor(var.timeout_seconds) == var.timeout_seconds
    error_message = "Native Helm timeout must be an integer between 300 and 1800 seconds."
  }
}
variable "routing_mode" {
  type    = string
  default = "auto"
  validation {
    condition     = contains(["auto", "direct", "prefixaware", "kvaware"], var.routing_mode)
    error_message = "Choose auto, direct, prefixaware or kvaware routing."
  }
}
variable "lmcache_mode" {
  type    = string
  default = "recipe"
  validation {
    condition     = contains(["recipe", "disabled", "mp", "inprocess"], var.lmcache_mode)
    error_message = "Choose recipe, disabled, mp or inprocess LMCache."
  }
}
variable "lmcache_cpu_memory_gb" {
  type    = number
  default = null
}
variable "lmcache_chunk_size" {
  type    = number
  default = null
}
variable "lmcache_mamba_cache_mode" {
  type    = string
  default = null
}
