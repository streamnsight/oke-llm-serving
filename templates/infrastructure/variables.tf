# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "tenancy_ocid" { type = string }
variable "compartment_ocid" {
  type    = string
  default = null
}
variable "compartment_id" {
  type    = string
  default = null
}
variable "region" { type = string }
variable "cluster_id" { type = string }
variable "availability_domain" { type = string }
variable "gpu_shape" { type = string }
variable "node_count" {
  description = "Retained GPU hosts, not individual GPUs."
  type        = number
  default     = 1
  validation {
    condition     = var.node_count >= 1 && floor(var.node_count) == var.node_count
    error_message = "Use a positive integer host count."
  }
}
variable "platform_name" {
  description = "Stable pool/platform identity, independent of models and discovery runs."
  type        = string
  default     = "llm-platform"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.platform_name))
    error_message = "Use a DNS-safe platform name of 2–32 characters."
  }
}
variable "skip_gpu_allocation" {
  type        = bool
  default     = false
  description = "Temporary debug switch: create platform resources and install CPU controllers without allocating GPU hosts. Never enable after GPU allocation."
}
variable "advanced_settings" {
  type    = bool
  default = false
}
variable "rdma_mode" {
  description = "Auto follows the discovery execution topology; hardware RDMA support alone does not require a fabric."
  type        = string
  default     = "auto"
  validation {
    condition     = contains(["auto", "ethernet", "rdma"], var.rdma_mode)
    error_message = "Choose auto, ethernet or rdma."
  }
}
variable "enable_lws" {
  description = "Install/reuse the shared LeaderWorkerSet controller for multi-node serving."
  type        = bool
  default     = false
}
variable "monitoring_enabled" {
  type    = bool
  default = true
}
variable "autoscaling_enabled" {
  description = "Install or reuse KEDA for later model workload autoscaling. Never scales GPU hosts."
  type        = bool
  default     = false
}
variable "enable_disaggregated_set" {
  type    = bool
  default = false
}
variable "lws_mode" {
  type    = string
  default = "managed"
  validation {
    condition     = contains(["managed", "reuse", "retire"], var.lws_mode)
    error_message = "Select managed, reuse or retire."
  }
}
variable "prometheus_mode" {
  type    = string
  default = "managed"
  validation {
    condition     = contains(["managed", "reuse", "retire"], var.prometheus_mode)
    error_message = "Select managed, reuse or retire."
  }
}
variable "keda_mode" {
  type    = string
  default = "managed"
  validation {
    condition     = contains(["managed", "reuse", "retire"], var.keda_mode)
    error_message = "Select managed, reuse or retire."
  }
}
variable "cluster_authorization_mode" {
  description = "IAM grants only CLUSTER_MANAGE on this exact cluster for Kubernetes administration. RBAC instead requires applying the generated binding separately. Neither mode grants OCI node-pool management to pipelines."
  type        = string
  default     = "iam"
  validation {
    condition     = contains(["iam", "rbac"], var.cluster_authorization_mode)
    error_message = "Choose iam or rbac."
  }
}
variable "os_version" {
  type    = string
  default = "8"
  validation {
    condition     = contains(["8", "9"], var.os_version)
    error_message = "Select Oracle Linux 8 or 9."
  }
}
variable "boot_volume_gib" {
  description = "GPU host boot disk. Increase for the largest planned checkpoint/cache before allocation."
  type        = number
  default     = 200
  validation {
    condition     = var.boot_volume_gib >= 200 && floor(var.boot_volume_gib) == var.boot_volume_gib
    error_message = "Use an integer boot disk size of at least 200 GiB."
  }
}
variable "observation_id" {
  description = "Optional capacity report identifier. Null requests a fresh report on each provisioning plan/apply."
  type        = string
  default     = null
}
variable "gpu_image_id" {
  type    = string
  default = null
}
variable "subnet_id" {
  type    = string
  default = null
}
variable "pod_subnet_id" {
  type    = string
  default = null
}
variable "devops_subnet_id" {
  type    = string
  default = null
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
variable "rdma_resource_name" {
  description = "Optional existing RDMA extended resource; otherwise detect a unique resource on the pool."
  type        = string
  default     = null
}
variable "model_storage_mode" {
  description = "Optional model-data staging, independent of pipeline software artifacts."
  type        = string
  default     = "direct_huggingface"
  validation {
    condition     = contains(["direct_huggingface", "object_storage"], var.model_storage_mode)
    error_message = "Choose direct_huggingface or object_storage."
  }
}
variable "model_staging_image" {
  description = "Digest-pinned CPU image built from modules/llm-deployment/model-storage/image/Dockerfile; needed only for optional Object Storage staging."
  type        = string
  default     = null
}
variable "model_staging_cpu_shape" {
  description = "Optional existing CPU shape override. Defaults to a CPU shape observed in the existing cluster pools; runner validates actual nodes."
  type        = string
  default     = null
}
