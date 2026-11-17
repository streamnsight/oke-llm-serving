# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12" } }
}
locals {
  target = { cluster_id = "cluster", runner_subnet_id = "subnet", runner_nsg_ids = [], metadata_ready = true, issues = [] }
}
module "first" {
  source         = "../../.."
  name           = "same-model"
  compartment_id = "compartment"
  target         = local.target
}
module "second" {
  source         = "../../.."
  name           = "same-model"
  compartment_id = "compartment"
  target         = local.target
}
output "first" { value = module.first.resources }
output "second" { value = module.second.resources }
