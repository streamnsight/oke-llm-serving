# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { external = { source = "hashicorp/external", version = "~> 2.3" } }
}
variable "query" {
  description = "Discovery request encoded as external-provider strings; authentication comes from the execution environment."
  type        = map(string)
}
data "external" "scan" {
  program = ["bash", "${path.module}/scripts/discover-oci.sh"]
  query   = merge(var.query, { gpu_catalog = file("${path.module}/../accelerator-inventory/data/gpus.json") })
}
output "result" {
  description = "Subscribed regions, inventory, entitlement and diagnostic capacity observations."
  value       = jsondecode(data.external.scan.result.result)
}
