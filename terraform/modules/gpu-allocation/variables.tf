# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "tenancy_ocid" { type = string }
variable "compartment_id" { type = string }
variable "cluster_id" { type = string }
variable "region" { type = string }
variable "availability_domain" { type = string }
variable "subnet_id" { type = string }
variable "gpu_image_id" { type = string }
variable "gpu_shape" { type = string }
variable "node_count" {
  type = number
  validation {
    condition     = var.node_count >= 1 && floor(var.node_count) == var.node_count
    error_message = "node_count is a positive integer of instances, not GPUs."
  }
}
variable "name" { type = string }
variable "requires_rdma" { type = bool }
variable "observation_id" { type = string }
variable "cpu_image_id" { type = string }
variable "cpu_node_count" {
  type    = number
  default = 1
  validation {
    condition     = var.cpu_node_count >= 1 && floor(var.cpu_node_count) == var.cpu_node_count
    error_message = "At least one CPU node is required for controllers/router and validation clients."
  }
}
variable "cpu_subnet_id" { type = string }
variable "boot_volume_gib" {
  type    = number
  default = 200
}
variable "pod_subnet_id" {
  description = "Optional pod subnet for VCN-native CNI; null reuses the node subnet."
  type        = string
  default     = null
}
variable "specification_id" {
  description = "Dependency on the caller's validated specification, without deferring native inventory reads."
  type        = string
  default     = "standalone"
}
