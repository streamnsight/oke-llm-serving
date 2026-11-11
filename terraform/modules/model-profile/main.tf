terraform {
  required_version = ">= 1.5.0"
  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

# Python source is bundled with this repository; no pip installation is required.
data "external" "model" {
  program = [var.python_executable, "${path.module}/inspect.py"]
  query = {
    model          = var.model
    revision       = var.revision
    checkpoint     = var.checkpoint == null ? "" : var.checkpoint
    context_length = tostring(var.context_length)
    concurrency    = tostring(var.concurrency)
    kv_dtype       = var.kv_dtype
    weight_dtype   = var.weight_dtype
    runtime_gib    = tostring(var.runtime_gib)
    margin         = tostring(var.margin)
  }
}

output "profile" {
  description = "Versioned model profile. Unsupported estimates retain metadata and explain their limits."
  value       = jsondecode(data.external.model.result.profile_json)
}
