# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "tenancy_ocid" {
  description = "RMS tenancy root; used for capacity reports."
  type        = string
}
variable "region" {
  description = "Internal initial OCI endpoint, normally injected by RMS. Null uses CLI defaults; the tenancy home region is discovered automatically."
  default     = null
  type        = string
}
variable "model" {
  description = "Public Hugging Face repository URL or owner/model."
  type        = string

  nullable = false
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
  description = "Simultaneously active sequences per serving replica at the specified context length; complete additional replicas repeat this memory budget."
  type        = number
  default     = 1
}
variable "observation_id" {
  description = "Snapshot label. Discovery requests fresh reports whenever its data source is read."
  type        = string
  default     = "initial"
}
variable "regions" {
  description = "Blank rows are ignored. An empty effective list selects every READY subscription; explicit names are trimmed and deduplicated."
  type        = set(string)
  default     = []
  nullable    = false
}
variable "shape_names" {
  description = "Blank rows are ignored. An empty effective list selects all visible GPU shapes; explicit names are trimmed and deduplicated."
  type        = set(string)
  default     = []
  nullable    = false
}
variable "compartment_id" {
  description = "Intended deployment compartment for quota headroom; null checks root entitlement only."
  type        = string
  default     = null
}
variable "compartment_ocid" {
  description = "Resource Manager stack compartment, automatically supplied by RMS."
  type        = string
  default     = null
}
variable "publish_infrastructure_bundles" {
  description = "Publish configured infrastructure ZIPs for confirmed options. The HTML report is always published on Apply, including when ZIP publication is disabled. Allocates no GPU hosts."
  type        = bool
  default     = true
}
variable "artifact_compartment_id" {
  description = "Optional artifact-storage compartment override. Defaults to the RMS stack compartment."
  type        = string
  default     = null
}
variable "par_lifetime_hours" {
  type    = number
  default = 24
}

variable "checkpoint_file" {
  type        = string
  default     = ""
  description = "Optional exact checkpoint filename for an otherwise ambiguous variant (single-file formats only)."
}
variable "weight_budget_gb" {
  type        = number
  default     = 0
  description = "Explicit native weight planning baseline in decimal GB; zero uses checkpoint evidence."
  validation {
    condition     = var.weight_budget_gb >= 0
    error_message = "Weight budget must be nonnegative."
  }
}
variable "planning_budget_gb" {
  type        = number
  default     = 0
  description = "Explicit aggregate planning payload in decimal GB, including cache/workspace/margin but excluding per-GPU runtime; zero estimates from metadata."
  validation {
    condition     = var.planning_budget_gb >= 0
    error_message = "Planning budget must be nonnegative."
  }
}
variable "unknown_cache_fraction" {
  type        = number
  default     = 0.25
  description = "Uncalibrated cache allowance as a fraction of weights when attention dimensions are absent; not an upper bound."
  validation {
    condition     = var.unknown_cache_fraction >= 0
    error_message = "Cache allowance must be nonnegative."
  }
}
variable "workspace_fraction" {
  type        = number
  default     = 0.10
  description = "Uncalibrated workspace/repacking allowance as a fraction of weights for heuristic sizing; not an upper bound."
  validation {
    condition     = var.workspace_fraction >= 0
    error_message = "Workspace allowance must be nonnegative."
  }
}

variable "max_hosts_per_replica" {
  description = "Maximum hosts to consider for one model replica; multi-host options require upstream PP support and full capacity/headroom."
  type        = number
  default     = 8
  validation {
    condition     = var.max_hosts_per_replica >= 1 && var.max_hosts_per_replica <= 32 && floor(var.max_hosts_per_replica) == var.max_hosts_per_replica
    error_message = "Maximum hosts per replica must be an integer between 1 and 32."
  }
}
