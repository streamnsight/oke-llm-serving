# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "tenancy_ocid" { type = string }
variable "compartment_ocid" {
  description = "Automatically supplied by Resource Manager."
  type        = string
  default     = null
}
variable "compartment_id" {
  type    = string
  default = null
}
variable "provision_resources" {
  description = "False previews resolved infrastructure without creating OCI resources. Enable only after reviewing the preview. Do not disable again on an allocated stack."
  type        = bool
  default     = false
}
variable "advanced_settings" {
  description = "Show optional RMS overrides."
  type        = bool
  default     = false
}
variable "inspect_serving_image" {
  description = "Also inspect the serving image's digest-verified CUDA metadata during preview. Provisioning always performs this read. Requires Docker Registry/CDN access."
  type        = bool
  default     = false
}
variable "os_version" {
  description = "Oracle Linux major version for automatic OKE image selection."
  type        = string
  default     = "8"
  validation {
    condition     = contains(["8", "9"], var.os_version)
    error_message = "Select Oracle Linux 8 or 9."
  }
}
variable "region" {
  default = null
  type    = string
}
variable "cluster_id" { type = string }
variable "availability_domain" {
  default = null
  type    = string
}
variable "subnet_id" {
  type    = string
  default = null
}
variable "cpu_subnet_id" {
  type    = string
  default = null
}
variable "network_compartment_id" {
  description = "Optional RMS network-picker compartment. Does not change the cluster's derived VCN."
  type        = string
  default     = null
}
variable "network_vcn_id" {
  description = "Optional RMS subnet-picker filter. Must equal the selected cluster's VCN."
  type        = string
  default     = null
}
variable "devops_subnet_id" {
  type    = string
  default = null
}
variable "gpu_image_id" {
  type    = string
  default = null
}
variable "cpu_image_id" {
  type    = string
  default = null
}
variable "gpu_shape" {
  default = null
  type    = string
}
variable "name" {
  type    = string
  default = "llm-serving"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.name))
    error_message = "Use a DNS-safe deployment name of 2–32 characters."
  }
}
variable "node_count" {
  default = null
  type    = number
}
variable "requires_rdma" {
  default = null
  type    = bool
}
variable "tensor_parallel_size" {
  default = null
  type    = number
}
variable "pipeline_parallel_size" {
  default = null
  type    = number
}
variable "replicas" {
  default = null
  type    = number
}
variable "model" {
  default = null
  type    = string
}
variable "model_revision" {
  default = null
  type    = string
  validation {
    condition     = var.model_revision == null ? true : can(regex("^[a-fA-F0-9]{40}$", var.model_revision))
    error_message = "Deploy an immutable model commit SHA."
  }
}
variable "engine_image" {
  default = null
  type    = string
  validation {
    condition     = var.engine_image == null ? true : trimspace(var.engine_image) == "" ? true : can(regex("@sha256:[a-f0-9]{64}$", var.engine_image))
    error_message = "engine_image must be pinned by SHA256 digest."
  }
}
variable "engine_version" {
  default = null
  type    = string
}
variable "context_length" {
  default = null
  type    = number
  validation {
    condition     = var.context_length == null ? true : var.context_length >= 256 && floor(var.context_length) == var.context_length
    error_message = "Initial chat validation requires context_length >= 256."
  }
}
variable "concurrency" {
  default = null
  type    = number
  validation {
    condition     = var.concurrency == null ? true : var.concurrency >= 1 && var.concurrency <= 256 && floor(var.concurrency) == var.concurrency
    error_message = "Initial validation supports 1–256 concurrent requests."
  }
}
variable "kv_dtype" {
  default = null
  type    = string
}
variable "observation_id" {
  default     = null
  description = "Change before an allocation attempt to obtain a fresh capacity snapshot."
  type        = string
}
variable "assessment_id" {
  default = null
  type    = string
}
variable "cpu_node_count" {
  type    = number
  default = null
}
variable "cpu_ocpus" {
  type    = number
  default = null
}
variable "cpu_memory_gib" {
  type    = number
  default = null
}
variable "boot_volume_gib" {
  type    = number
  default = null
}
variable "rdma_network_attachment" {
  description = "Existing Multus NetworkAttachmentDefinition name or namespace/name, when required by the OKE-managed RDMA/SR-IOV network configuration. The stack does not create or configure the cluster network."
  type        = string
  default     = null
}
variable "rdma_resource_name" {
  description = "Optional existing cluster RDMA extended-resource name. Null detects a unique advertised RDMA resource; no device plugins are installed."
  type        = string
  default     = null
  validation {
    condition     = try(trimspace(var.rdma_resource_name), "") == "" ? true : can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?/[A-Za-z0-9][-A-Za-z0-9_.]*$", var.rdma_resource_name))
    error_message = "Use a qualified existing resource name, such as nvidia.com/rdma_shared_device_a."
  }
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
  default = null
  validation {
    condition     = var.benchmark_output_tokens == null ? true : var.benchmark_output_tokens >= 1 && floor(var.benchmark_output_tokens) == var.benchmark_output_tokens
    error_message = "benchmark_output_tokens must be a positive integer."
  }
}
variable "benchmark_input_tokens" {
  type    = number
  default = null
  validation {
    condition     = var.benchmark_input_tokens == null ? true : var.benchmark_input_tokens >= 1 && floor(var.benchmark_input_tokens) == var.benchmark_input_tokens
    error_message = "benchmark_input_tokens must be a positive integer."
  }
}
variable "pod_subnet_id" {
  type    = string
  default = null
}
variable "runtime_gib" {
  type    = number
  default = null
}
variable "margin" {
  type    = number
  default = null
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

variable "discovery" {
  description = "The single discovery deployment_inputs JSON object, or its inner discovery object."
  type        = any
  default     = null
  validation {
    condition     = var.discovery == null || can(var.discovery.discovery.profile.model.resolved_revision) || can(var.discovery.profile.model.resolved_revision)
    error_message = "Pass the deployment_inputs object or its discovery member, not the Terraform output metadata wrapper."
  }
}
variable "selection_id" {
  description = "Candidate or expert sizing-option ID from the discovery assessment."
  type        = string
  default     = null
}
variable "engine_channel" {
  description = "Deployment choice among assessed engines."
  type        = string
  default     = "recommended"
  validation {
    condition     = contains(["recommended", "stable", "nightly"], var.engine_channel)
    error_message = "Choose recommended, stable or nightly."
  }
}
variable "engine_platform" {
  description = "Auto follows the selected GPU node CPU architecture; an explicit image override must match."
  type        = string
  default     = "auto"
  validation {
    condition     = contains(["auto", "linux/amd64", "linux/arm64"], var.engine_platform)
    error_message = "Choose auto, linux/amd64 or linux/arm64."
  }
}
variable "recipe_features" {
  description = "Optional features identified by discovery, selected at deployment."
  type        = set(string)
  default     = []
  nullable    = false
}
variable "discovery_json" {
  description = "RMS: paste one deployment_handoffs[selection].inline_json, not the full report. Resource Manager limits each variable to 8192 bytes."
  type        = string
  default     = null
  validation {
    condition     = try(trimspace(var.discovery_json), "") == "" || can(jsondecode(var.discovery_json).discovery.profile.model.resolved_revision) || can(jsondecode(var.discovery_json).profile.model.resolved_revision)
    error_message = "Paste valid deployment_inputs JSON or its discovery object."
  }
  validation {
    condition     = var.discovery_json == null ? true : length(base64encode(var.discovery_json)) * 3 / 4 - length(regexall("=", base64encode(var.discovery_json))) <= 8000
    error_message = "Inline handoff exceeds the RMS-safe 8000-byte budget. Use a compact per-selection handoff or discovery_object_uri with discovery_sha256."
  }
}
variable "discovery_object_uri" {
  description = "Authenticated large-payload transport: oci://REGION/NAMESPACE/BUCKET/OBJECT. No public URL or PAR is required."
  type        = string
  default     = null
  validation {
    condition     = try(trimspace(var.discovery_object_uri), "") == "" || can(regex("^oci://[^/]+/[^/]+/[^/]+/.+$", var.discovery_object_uri))
    error_message = "Use oci://REGION/NAMESPACE/BUCKET/OBJECT."
  }
}
variable "discovery_sha256" {
  description = "SHA256 of the Object Storage JSON bytes; required for object transport."
  type        = string
  default     = null
  validation {
    condition     = try(trimspace(var.discovery_sha256), "") == "" || can(regex("^[a-f0-9]{64}$", var.discovery_sha256))
    error_message = "Use a lowercase SHA256 hex digest."
  }
}

variable "worker_nsg_ids" {
  type    = list(string)
  default = null
}

variable "pod_nsg_ids" {
  type    = list(string)
  default = null
}

variable "devops_nsg_ids" {
  type    = list(string)
  default = null
}
