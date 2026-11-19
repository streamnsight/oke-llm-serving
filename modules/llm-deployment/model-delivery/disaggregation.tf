# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  pd_enabled = var.serving_mode == "disaggregated"
  pd = {
    enabled       = local.pd_enabled, prefill_replicas = local.pd_enabled ? var.prefill_replicas : 0,
    chat_probe    = try(local.profile.model.chat_template_available, false),
    connector     = "NixlConnector", load_failure_policy = "recompute", transport = "UCX TCP with CUDA staging",
    effectiveness = "not_yet_observed; successful inference alone does not prove transfer"
  }
}
resource "terraform_data" "pd_contract" {
  input = local.pd
  lifecycle {
    precondition {
      condition     = !local.pd_enabled || module.cache_capabilities.assessment.disaggregation.selectable
      error_message = "Native P/D is unavailable: ${join(" ", module.cache_capabilities.assessment.disaggregation.reasons)}"
    }
    precondition {
      condition     = !local.pd_enabled || (!local.lmcache_enabled && var.routing_mode == "auto" && !var.autoscaling.enabled && var.api_frontend == "python")
      error_message = "Native P/D requires LMCache disabled (or a recipe without LMCache), routing_mode=auto, the Python frontend and fixed replicas. The adapter owns orchestration and native KV transfer."
    }
    precondition {
      condition     = !local.pd_enabled || local.defaults.MODEL_ID == var.model.model.repository
      error_message = "Changing the model ID for native P/D requires fresh discovery metadata; a different model cannot reuse this compatibility assessment."
    }
    precondition {
      condition     = !local.pd_enabled || tonumber(local.defaults.CONTEXT_LENGTH) >= 256
      error_message = "Native P/D validation requires at least 256 context tokens for a bounded chat/completions transfer probe."
    }
  }
}
