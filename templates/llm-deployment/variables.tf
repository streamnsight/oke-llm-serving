# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "tenancy_ocid" { type = string }
variable "cluster_id" { type = string }
variable "advanced_settings" {
  type    = bool
  default = false
}
variable "compartment_id" {
  type    = string
  default = null
}
variable "gpu_pool_id" {
  type    = string
  default = null
}
variable "gpu_pool_compartment_id" {
  type    = string
  default = null
}
variable "platform_name" {
  type    = string
  default = null
}
variable "runner_subnet_id" {
  type    = string
  default = null
}
variable "runner_nsg_ids" {
  type    = list(string)
  default = null
}
variable "rdma_resource_name" {
  type    = string
  default = null
}
variable "compartment_ocid" {
  type    = string
  default = null
}
variable "region" {
  type    = string
  default = null
}
variable "model_name" {
  type    = string
  default = null
}
variable "namespace" {
  type    = string
  default = null
}
variable "model_id" {
  type    = string
  default = null
}
variable "model_revision" {
  type    = string
  default = null
}
variable "serving_image" {
  type    = string
  default = null
}
variable "tensor_parallel_size" {
  type    = number
  default = null
}
variable "pipeline_parallel_size" {
  type    = number
  default = null
}
variable "hosts_per_replica" {
  type    = number
  default = null
}
variable "gpus_per_pod" {
  type    = number
  default = null
}
variable "replicas" {
  type    = number
  default = null
}
variable "context_length" {
  type    = number
  default = null
}
variable "concurrency" {
  type    = number
  default = null
}
variable "hf_token_secret" {
  type    = string
  default = ""
}
variable "storage_mode" {
  type    = string
  default = "direct_hf"
}
variable "model_pvc_name" {
  type    = string
  default = ""
}
variable "model_path" {
  type    = string
  default = "/models/model"
}
variable "workspace_gib" {
  type    = number
  default = null
}
variable "router_enabled" {
  type    = bool
  default = false
}
variable "inference_probe" {
  type    = string
  default = "none"
}
variable "benchmark_backend" {
  type    = string
  default = "unsupported"
}
variable "autoscaling_enabled" {
  type    = bool
  default = false
}
variable "min_replicas" {
  type    = number
  default = 1
}
variable "max_replicas" {
  type    = number
  default = 1
}
variable "prometheus_url" {
  type    = string
  default = ""
}
variable "target_inflight" {
  type    = number
  default = 8
}
variable "model_staging_image" {
  type    = string
  default = null
}
variable "model_staging_cpu_shape" {
  type    = string
  default = null
}
