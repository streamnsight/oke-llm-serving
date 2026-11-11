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
  description = "GPU shape names to inspect. Empty means all visible GPU shapes for inventory."
  type        = list(string)
  default     = []
}
variable "compartment_id" {
  description = "Target compartment for entitlement headroom; defaults to tenancy root."
  type        = string
  default     = null
}
variable "regions" {
  description = "Subscribed regions to scan. Empty selects only the profile's configured region."
  type        = list(string)
  default     = []
}
variable "max_limit_checks" {
  description = "Maximum resource-availability calls across this inventory run."
  type        = number
  default     = 100
  validation {
    condition     = var.max_limit_checks >= 0 && var.max_limit_checks <= 1000 && floor(var.max_limit_checks) == var.max_limit_checks
    error_message = "Use an integer between 0 and 1000."
  }
}
