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
    operation           = "capacity"
    profile             = var.profile
    config_file         = var.config_file == null ? "" : var.config_file
    auth                = var.auth
    tenancy_id          = var.tenancy_id == null ? "" : var.tenancy_id
    shape_names         = length(var.shape_names) == 0 ? "" : jsonencode(var.shape_names)
    region              = var.region
    availability_domain = var.availability_domain
    fault_domain        = var.fault_domain == null ? "" : var.fault_domain
    requested_instances = tostring(var.requested_instances)
  }
}

output "result" {
  description = "Timestamped discovery observations; callers must inspect completeness and per-query errors."
  value       = jsondecode(data.external.discovery.result.result_json)
}
