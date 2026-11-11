terraform {
  required_version = ">= 1.5.0"
  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

# External analysis is opt-in. RMS can consume a previously generated profile.
data "external" "model" {
  count   = var.profile_json == null && var.enable_external_analysis ? 1 : 0
  program = [var.python_executable, "${path.module}/inspect.py"]
  query = {
    model          = var.model == null ? "" : var.model
    revision       = var.revision
    checkpoint     = var.checkpoint == null ? "" : var.checkpoint
    context_length = tostring(var.context_length)
    concurrency    = tostring(var.concurrency)
    kv_dtype       = var.kv_dtype
    weight_dtype   = var.weight_dtype
    runtime_gib    = tostring(var.runtime_gib)
    margin         = tostring(var.margin)
  }
  lifecycle {
    precondition {
      condition     = var.model != null && var.model != ""
      error_message = "External analysis requires a model identifier."
    }
  }
}

output "profile" {
  description = "Versioned model profile. Unsupported estimates retain metadata and explain their limits."
  value       = var.profile_json != null ? jsondecode(var.profile_json) : try(jsondecode(data.external.model[0].result.profile_json), null)
  precondition {
    condition     = var.profile_json != null || var.enable_external_analysis
    error_message = "Supply profile_json for runtime-free execution, or explicitly enable_external_analysis on a prepared Python runner."
  }
}
