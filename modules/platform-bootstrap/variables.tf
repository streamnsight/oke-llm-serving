# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "tenancy_ocid" { type = string }
variable "compartment_id" { type = string }
variable "name" { type = string }
variable "subnet_id" { type = string }
variable "nsg_ids" {
  type    = list(string)
  default = []
}
variable "config" {
  description = "Platform specification and retained allocation identifiers. Contains no model settings."
  type        = any
}
