# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "profile" { type = any }
variable "assessment" { type = any }
variable "regions" { type = any }
variable "options" { type = any }
variable "publications" { type = any }
variable "model_publications" {
  type    = any
  default = {}
}
variable "publication" {
  type    = any
  default = null
}
variable "scan" { type = any }
variable "serving_configuration" { type = any }
