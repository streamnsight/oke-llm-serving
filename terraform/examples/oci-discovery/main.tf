terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}

# Local DEFAULT profile authentication; RMS supplies its own credentials.
provider "oci" {
  region = var.region
}

variable "tenancy_ocid" {
  description = "Root tenancy OCID; RMS prepopulates this variable."
  type        = string
}
variable "region" {
  description = "Region for this stack; RMS prepopulates it."
  type        = string
}
variable "compartment_id" {
  description = "Target for entitlement checks; null uses root, not a child compartment."
  type        = string
  default     = null
}
variable "shape_names" {
  type    = set(string)
  default = ["VM.GPU.A10.1"]
}
variable "availability_domain" {
  description = "Set to create a capacity report. Null performs only native data-source inventory."
  type        = string
  default     = null
}
variable "observation_id" {
  description = "Change before a fresh capacity assessment."
  type        = string
  default     = "initial"
}

module "inventory" {
  source         = "../../modules/accelerator-inventory"
  tenancy_ocid   = var.tenancy_ocid
  region         = var.region
  compartment_id = var.compartment_id
  shape_names    = var.shape_names
}

module "capacity" {
  count               = var.availability_domain == null ? 0 : 1
  source              = "../../modules/capacity-assessment"
  tenancy_ocid        = var.tenancy_ocid
  region              = var.region
  availability_domain = var.availability_domain
  shape_names         = var.shape_names
  observation_id      = var.observation_id
}

output "inventory" {
  value = module.inventory.result
}
output "capacity" {
  value = [for report in module.capacity : report.result]
}
