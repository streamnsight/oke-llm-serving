# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "mode" {
  type    = string
  default = "direct_huggingface"
  validation {
    condition     = contains(["direct_huggingface", "object_storage"], var.mode)
    error_message = "Use direct_huggingface or object_storage."
  }
}
variable "name" {
  type    = string
  default = "model"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.name))
    error_message = "name must be a lowercase Kubernetes name of 2 to 32 characters."
  }
}
variable "tenancy_ocid" {
  type    = string
  default = null
}
variable "compartment_id" {
  type    = string
  default = null
}
variable "project_id" {
  type    = string
  default = null
}
variable "artifact_repository_id" {
  type    = string
  default = null
}
variable "cluster_id" {
  type    = string
  default = null
}
variable "cluster_compartment_id" {
  type    = string
  default = null
}
variable "cluster_type" {
  type    = string
  default = null
}
variable "region" {
  type    = string
  default = null
}
variable "kubernetes_version" {
  type    = string
  default = null
}
variable "subnet_id" {
  type    = string
  default = null
}
variable "nsg_ids" {
  type    = list(string)
  default = []
}
variable "namespace" {
  description = "Dedicated, externally bootstrapped namespace. Defaults to <name>-staging."
  type        = string
  default     = null
  validation {
    condition     = var.namespace == null ? true : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a Kubernetes DNS label."
  }
}
variable "service_account" {
  type    = string
  default = "model-stager"
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.service_account))
    error_message = "service_account must be a Kubernetes DNS label."
  }
}
variable "model" {
  description = "Explicit selected snapshot file allowlist; revision is a resolved Hub commit, variant names the selected checkpoint format. No model code is executed."
  type = object({
    id    = string, revision = string, variant = string
    files = list(object({ path = string, size_bytes = number, sha256 = optional(string) }))
  })
  default = null
  validation {
    condition = var.model == null ? true : try((
      can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$", var.model.id)) &&
      can(regex("^[a-f0-9]{40}$", var.model.revision)) &&
      can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$", var.model.variant)) && length(var.model.files) > 0 &&
      length(distinct([for f in var.model.files : f.path])) == length(var.model.files) &&
      alltrue([for f in var.model.files :
        can(regex("^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$", f.path)) &&
        !anytrue([for p in split("/", f.path) : contains([".", ".."], p)]) &&
        f.size_bytes >= 0 && floor(f.size_bytes) == f.size_bytes &&
        (f.sha256 == null ? true : can(regex("^[a-f0-9]{64}$", f.sha256)))
      ])
    ), false)
    error_message = "Use owner/model, a lowercase 40-hex commit SHA, a named variant and unique safe relative files with integer sizes and optional lowercase SHA256."
  }
}
variable "staging_image" {
  description = "Required for Object Storage: tested linux/amd64 digest image with Bash, curl, jq, coreutils and OCI CLI supporting oke_workload_identity. See image/Dockerfile."
  type        = string
  default     = null
  validation {
    condition     = var.staging_image == null ? true : can(regex("^[A-Za-z0-9][A-Za-z0-9./:_-]*@sha256:[a-f0-9]{64}$", var.staging_image))
    error_message = "staging_image must be an image reference pinned by sha256 digest."
  }
}
variable "scratch_gib" {
  description = "Retained RWO scratch PVC. One shard at a time; must fit the largest allowlisted file plus headroom."
  type        = number
  default     = 64
  validation {
    condition     = var.scratch_gib >= 50 && floor(var.scratch_gib) == var.scratch_gib
    error_message = "scratch_gib must be an integer of at least 50 GiB (OCI Block Volume minimum)."
  }
}
variable "storage_class" {
  type    = string
  default = "oci-bv"
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9.-]*$", var.storage_class))
    error_message = "storage_class must be an explicit Kubernetes storage class name."
  }
}
variable "deadline_seconds" {
  type    = number
  default = 14400
  validation {
    condition     = var.deadline_seconds >= 300 && var.deadline_seconds <= 25200 && floor(var.deadline_seconds) == var.deadline_seconds
    error_message = "deadline_seconds must be an integer from 300 to 25200, leaving headroom within the DevOps eight-hour command limit."
  }
}
variable "cpu_node_selector" {
  description = "Labels selecting a confirmed existing CPU pool. Required in staging mode; no GPU fallback."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for key, value in var.cpu_node_selector : can(regex("^[A-Za-z0-9./_-]+$", key)) && can(regex("^[A-Za-z0-9._-]+$", value))])
    error_message = "CPU node selector keys/values must be literal Kubernetes labels."
  }
}
variable "hf_token_secret_id" {
  description = "Optional OCI Vault secret containing a Hugging Face hf_ token. The token itself never enters Terraform or pipeline parameters."
  type        = string
  default     = null
  validation {
    condition     = var.hf_token_secret_id == null ? true : can(regex("^ocid1\\.vaultsecret\\.[A-Za-z0-9._-]+$", var.hf_token_secret_id))
    error_message = "hf_token_secret_id must be a Vault secret OCID."
  }
}
variable "hf_token_secret_compartment_id" {
  type    = string
  default = null
}
