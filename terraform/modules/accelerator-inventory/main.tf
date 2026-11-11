terraform {
  required_version = ">= 1.5.0"
  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

data "external" "discovery" {
  program = [var.python_executable, "${path.module}/discover.py"]
  query = {
    operation        = "inventory"
    profile          = var.profile
    config_file      = var.config_file == null ? "" : var.config_file
    auth             = var.auth
    tenancy_id       = var.tenancy_id == null ? "" : var.tenancy_id
    shape_names      = length(var.shape_names) == 0 ? "" : jsonencode(var.shape_names)
    compartment_id   = var.compartment_id == null ? "" : var.compartment_id
    regions          = length(var.regions) == 0 ? "" : jsonencode(var.regions)
    max_limit_checks = tostring(var.max_limit_checks)
  }
}

output "result" {
  description = "Timestamped discovery observations; callers must inspect completeness and per-query errors."
  value       = jsondecode(data.external.discovery.result.result_json)
}
