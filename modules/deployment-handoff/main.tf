# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "profile" { type = any }
variable "assessment" { type = any }
variable "serving_configuration" { type = any }
variable "observation_id" { type = string }
module "control_plane" { source = "../control-plane-sizing" }
locals {
  choices = concat(try(var.assessment.suggestions, []), try(var.assessment.candidates, []), try(var.assessment.sizing_options, []))
  # Keep every launch/feature setting and source hash. Drop other choices, report
  # diagnostics and the API's duplicate original argv (resolved args are retained).
  payloads = { for c in local.choices : c.id => { discovery = {
    schema_version = "3.0", observation_id = var.observation_id
    control_plane  = try(var.assessment.control_plane, null) != null ? var.assessment.control_plane : module.control_plane.requirements
    profile = {
      model  = { repository = var.profile.model.repository, resolved_revision = var.profile.model.resolved_revision }
      memory = { assumptions = { for k, v in var.profile.memory.assumptions : k => v if contains(["context_length", "concurrency", "kv_dtype", "runtime_allowance_gib", "safety_margin_fraction"], k) } }
    }
    assessment = { suggestions = [merge(
      { for k, v in c : k => v if contains(["id", "region", "availability_domain", "gpu_shape", "node_count", "tensor_parallel_size", "pipeline_parallel_size", "replicas", "requires_rdma", "capacity_observed_at", "estimated_rank_bytes", "configuration_status", "control_plane"], k) },
      { serving_configuration = merge(try(c.serving_configuration, var.serving_configuration), {
        recipe = merge(try(c.serving_configuration.recipe, var.serving_configuration.recipe), {
          api = { for k, v in try(c.serving_configuration.recipe.api, var.serving_configuration.recipe.api, {}) : k => v if k != "original_argv" }
        })
      }) }
    )] }
  } } }
  encoded = { for id, payload in local.payloads : id => jsonencode(payload) }
  bytes   = { for id, value in local.encoded : id => length(base64encode(value)) * 3 / 4 - length(regexall("=", base64encode(value))) }
}
output "handoffs" {
  description = "One frozen configuration per choice. Paste inline_json verbatim; use Object Storage when inline_json is null. Budget includes room for the RMS variable name."
  value = { for id, value in local.encoded : id => {
    selection_id = id, bytes = local.bytes[id], sha256 = sha256(value),
    inline_json  = local.bytes[id] <= 8000 ? value : null,
    object_json  = local.bytes[id] > 8000 ? value : null, transport = local.bytes[id] <= 8000 ? "inline_json" : "object_storage_required"
  } }
}
