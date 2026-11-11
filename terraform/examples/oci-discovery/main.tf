variable "compartment_id" {
  description = "Entitlement target. Null queries tenancy-root headroom, not a child compartment."
  type        = string
  default     = null
}
variable "regions" {
  type    = list(string)
  default = []
}
variable "shape_names" {
  type    = list(string)
  default = ["VM.GPU.A10.1"]
}
variable "capacity_region" {
  type    = string
  default = null
}
variable "availability_domain" {
  description = "Set together with capacity_region to request a fresh host-capacity report."
  type        = string
  default     = null
}

module "inventory" {
  source         = "../../modules/accelerator-inventory"
  compartment_id = var.compartment_id
  regions        = var.regions
  shape_names    = var.shape_names
}

module "capacity" {
  count               = var.availability_domain == null ? 0 : 1
  source              = "../../modules/capacity-assessment"
  region              = var.capacity_region
  availability_domain = var.availability_domain
  shape_names         = var.shape_names
}

output "inventory" {
  value = module.inventory.result
}
output "capacity" {
  value = [for report in module.capacity : report.result]
}
