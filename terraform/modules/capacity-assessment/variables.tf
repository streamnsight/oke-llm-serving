variable "profile" {
  description = "Local OCI configuration profile."
  type        = string
  default     = "DEFAULT"
}
variable "config_file" {
  description = "Optional OCI configuration file path; never key contents."
  type        = string
  default     = null
}
variable "auth" {
  description = "OCI authentication mode."
  type        = string
  default     = "config"
  validation {
    condition     = contains(["config", "instance_principal", "resource_principal"], var.auth)
    error_message = "Use config, instance_principal or resource_principal."
  }
}
variable "tenancy_id" {
  description = "Root tenancy OCID for principal authentication when it cannot be derived."
  type        = string
  default     = null
}
variable "python_executable" {
  description = "Python 3.11+ with the OCI SDK installed."
  type        = string
  default     = "python3"
}
variable "shape_names" {
  description = "Explicit shape names for the capacity report; counts represent instances."
  type        = list(string)
  validation {
    condition     = length(var.shape_names) > 0 && length(var.shape_names) <= 100 && alltrue([for shape in var.shape_names : length(trimspace(shape)) > 0])
    error_message = "Supply between 1 and 100 nonempty shape names."
  }
}
variable "region" {
  description = "OCI region containing the requested availability domain."
  type        = string
  nullable    = false
}
variable "availability_domain" {
  description = "Full tenancy-specific AD name from inventory."
  type        = string
  nullable    = false
}
variable "fault_domain" {
  description = "Optional fault-domain scope; not an OKE compute-cluster placement configuration."
  type        = string
  default     = null
}
variable "requested_instances" {
  description = "Instances required per shape; this is not an individual GPU count."
  type        = number
  default     = 1
  validation {
    condition     = var.requested_instances > 0 && floor(var.requested_instances) == var.requested_instances
    error_message = "requested_instances must be a positive integer."
  }
}
