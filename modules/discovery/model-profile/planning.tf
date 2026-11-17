# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Planning remains available independently of exact engine/architecture support.
# No remote model code or weight bodies are fetched.
locals {
  gguf_files           = [for f in try(local.info.siblings, []) : f if endswith(lower(f.rfilename), ".gguf")]
  other_weight_files   = [for f in try(local.info.siblings, []) : f if !strcontains(f.rfilename, "/") && can(regex("^(model|pytorch_model|consolidated).*\\.(bin|pt|pth)$", f.rfilename))]
  binary_index         = contains([for f in try(local.info.siblings, []) : f.rfilename], "pytorch_model.bin.index.json")
  selected_shard_files = local.has_index ? local.root_checkpoints : local.binary_index ? [for f in local.other_weight_files : f.rfilename] : []
  shard_ids            = [for name in local.selected_shard_files : regex("^(?:model|pytorch_model)-([0-9]+)-of-([0-9]+)\\.(?:safetensors|bin)$", name) if can(regex("^(?:model|pytorch_model)-([0-9]+)-of-([0-9]+)\\.(?:safetensors|bin)$", name))]
  complete_shards      = length(local.shard_ids) > 0 && length(local.shard_ids) == length(local.selected_shard_files) && length(distinct([for shard in local.shard_ids : tonumber(shard[0])])) == length(local.shard_ids) && alltrue([for shard in local.shard_ids : tonumber(shard[1]) == length(local.shard_ids) && tonumber(shard[0]) >= 1 && tonumber(shard[0]) <= length(local.shard_ids)])
  shard_sizes          = [for f in try(local.info.siblings, []) : coalesce(try(f.size, f.lfs.size, null), 0) if contains(local.selected_shard_files, f.rfilename)]
  safe_shard_sizes     = try(local.complete_shards && alltrue([for size in local.shard_sizes : size > 0]) ? sum(local.shard_sizes) : null, null)
  selected_checkpoint  = var.checkpoint_file != "" ? var.checkpoint_file : local.has_index ? "model.safetensors.index.json" : local.canonical ? "model.safetensors" : local.binary_index ? "pytorch_model.bin.index.json" : length(local.gguf_files) == 1 ? local.gguf_files[0].rfilename : length(local.other_weight_files) == 1 ? local.other_weight_files[0].rfilename : null
  selected_file_bytes  = try(one([for f in local.info.siblings : try(f.size, f.lfs.size) if f.rfilename == local.selected_checkpoint && !endswith(f.rfilename, ".index.json")]), null)
  # Counts describe the Hub's canonical safetensors, not an explicitly selected alternative.
  native_weight_bytes    = try(local.selected_checkpoint != null && var.checkpoint_file == "" && local.weights_supported ? local.weight_bytes : null, null)
  planning_weights       = try(coalesce(var.weight_budget_gb == 0 ? null : var.weight_budget_gb * 1e9, local.native_weight_bytes, local.selected_file_bytes, var.checkpoint_file == "" ? local.safe_shard_sizes : null), null)
  storage_conflict       = try(abs(local.native_weight_bytes - local.safe_shard_sizes) / max(local.native_weight_bytes, local.safe_shard_sizes) > 0.02, false)
  planning_weight_source = var.weight_budget_gb > 0 ? "user_weight_budget" : local.native_weight_bytes != null ? "hub_dtype_counts" : local.planning_weights != null ? "selected_checkpoint_file_sizes" : "missing_select_checkpoint_or_supply_weight_budget_gb"
  # Dense all-layer cache is a scenario for unknown/hybrid architectures, not an upper bound.
  dense_kv_scenario    = local.dimensions_valid ? 2 * local.layers * local.kv_heads * local.head_dim * (var.kv_dtype == "float32" ? 4 : 2) * var.context_length * var.concurrency : null
  planning_cache       = try(coalesce(local.kv_bytes, local.dense_kv_scenario, local.planning_weights * var.unknown_cache_fraction), null)
  workspace            = try(local.planning_weights * var.workspace_fraction, null)
  planning_base        = try((var.weight_budget_gb > 0 ? local.planning_weights : max(local.planning_weights, coalesce(local.safe_shard_sizes, local.planning_weights))) + local.planning_cache, null)
  planning_uncertainty = try(max(local.supported ? 0 : local.workspace, local.planning_base * var.margin), null)
  planning_payload     = var.planning_budget_gb > 0 ? var.planning_budget_gb * 1e9 : try(ceil(local.planning_base + local.planning_uncertainty), null)
  planning = {
    status                          = local.planning_payload == null ? "missing_inputs" : var.planning_budget_gb > 0 ? "user_declared" : local.supported ? "structural_estimate" : "heuristic_uncalibrated"
    weight_bytes                    = local.planning_weights
    weight_source                   = local.planning_weight_source
    storage_metadata_conflict       = local.storage_conflict
    payload_source                  = var.planning_budget_gb > 0 ? "user_payload_budget" : "component_estimate"
    full_attention_kv_bytes         = local.partial_full_kv_bytes
    cache_scenario_bytes            = local.planning_cache
    cache_source                    = local.kv_bytes != null ? "ordinary_full_context_attention" : local.dense_kv_scenario != null ? "all_layer_dense_surrogate_not_upper_bound" : "weight_fraction_uncalibrated"
    workspace_allowance_bytes       = local.supported ? 0 : local.workspace
    uncertainty_allowance_bytes     = local.planning_uncertainty
    payload_budget_bytes            = local.planning_payload
    runtime_allowance_per_gpu_bytes = local.runtime_bytes
    safety_margin_fraction          = var.margin
    unknown_cache_fraction          = var.unknown_cache_fraction
    workspace_fraction              = var.workspace_fraction
    context_within_declared_maximum = try(var.context_length <= local.max_context, null)
    formula                         = "base = native weight baseline + cache scenario; payload = base + max(workspace allowance, base * margin); each GPU separately reserves runtime allowance and 10% device headroom"
    interpretation                  = "Planning scenario, not a guaranteed upper bound, measured resident allocation or proof of per-rank fit. All expert weights remain resident; no CPU offload."
  }
}
