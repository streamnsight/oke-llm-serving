# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Read declarations, never execute remote model code. A PP declaration is source
# evidence; the selected image/workload still needs runtime validation.
data "http" "pp_support" {
  count              = var.recipe_api_enabled && try(can(regex("^[a-f0-9]{40}$", var.serving_resolution.engine.source_commit)), false) && !can(var.serving_resolution.engine.pipeline_parallel_support) ? 1 : 0
  url                = "https://raw.githubusercontent.com/vllm-project/vllm/${var.serving_resolution.engine.source_commit}/docs/models/supported_models.md"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = contains([200, 404], self.status_code)
      error_message = "Could not read pinned pipeline-parallel support declarations."
    }
  }
}
locals {
  # Evaluate each table with its own header. The upstream page also contains
  # plugin tables without a PP column; those must neither block nor prove PP.
  pp_tables = [for block in split("\n\n", replace(try(data.http.pp_support[0].response_body, ""), "\r\n", "\n")) : split("\n", trimspace(block)) if
    startswith(trimspace(block), "| Architecture") && try(strcontains(reverse(split("|", split("\n", trimspace(block))[0]))[1], "[PP]"), false)
  ]
  pp_source_architectures = [for arch in try(local.profile.architecture.architectures, []) : arch if anytrue([for line in flatten(local.pp_tables) : try(strcontains(split("|", line)[1], "`${arch}`") && strcontains(reverse(split("|", trimspace(line)))[1], "✅"), false)])]
  pp_evidence = try(var.serving_resolution.engine.pipeline_parallel_support, {
    architectures  = local.pp_source_architectures
    source_url     = try(data.http.pp_support[0].url, null)
    source_commit  = try(var.serving_resolution.engine.source_commit, null)
    interpretation = "Pinned upstream PP declaration; image association and actual runtime remain unvalidated."
  })
  pp_supported        = try(var.serving_resolution.engine.framework == "vllm" && var.serving_resolution.engine.multi_node_backend == "mp" && anytrue([for arch in local.profile.architecture.architectures : contains(local.pp_evidence.architectures, arch) && contains(var.serving_resolution.engine.architectures, arch)]), false)
  pp_weights          = try(coalesce(try(local.profile.memory.planning.weight_bytes, null), try(local.profile.memory.weight_bytes, null)), null)
  pp_cache            = try(coalesce(try(local.profile.memory.planning.cache_scenario_bytes, null), try(local.profile.memory.kv_bytes, null)), null)
  pp_dimensions_valid = try(alltrue([for n in [local.a.layers, local.a.heads, local.a.kv_heads, local.a.head_dim, local.a.hidden_size, local.a.vocab_size] : n > 0 && floor(n) == n]) && local.a.heads % local.a.kv_heads == 0 && local.pp_weights > 0 && local.pp_cache >= 0, false)
  pp_payload_scale    = try(max(1, local.api_budget / (local.pp_weights + local.pp_cache)), 1)
  pp_embedding_bytes  = try(2 * local.a.vocab_size * local.a.hidden_size * max(concat([2], [for dtype in keys(try(local.profile.weights.elements_by_dtype, {})) : lookup({ F64 = 8, F32 = 4, F16 = 2, BF16 = 2 }, dtype, 2)])...), 0)
  # Single-host successes remain single-host. Limit the product before building
  # rank records; zero capacity/entitlement never creates a selectable layout.
  pp_rows = [for row in local.suggestion_rows : row if local.pp_supported && local.pp_dimensions_valid && try(local.profile.memory.assumptions.context_length <= local.profile.architecture.declared_context_length, true) && try(local.profile.memory.assumptions.context_length <= local.api.model.context_length, true) && length(row.tp_options) == 0 && try(row.capacity_status == "positive" && row.capacity.available_instances >= 2 * var.replicas && row.entitled_instances >= 2 * var.replicas && row.gpu.gpus == row.shape.gpus, false) &&
  !anytrue([for arg in row.rendering.argv : contains(["--speculative-config", "--speculative-model", "--enable-expert-parallel", "--kv-transfer-config"], split("=", arg)[0])]) && !try(row.rendering.selection.pd != null, false) && !try(row.rendering.selection.kv_offload != null, false) && try(row.rendering.deployment_profile.lmcache.mode, var.serving_resolution.deployment_profile.lmcache.mode, "disabled") == "disabled"]
  pp_layouts = flatten([for row in local.pp_rows : [for tp in [1, 2, 4, 8] : [for pp in range(2, var.max_nodes_per_replica + 1) : {
    row = row, tp = tp, pp = pp
    # Reserve one additional average layer for stage imbalance. Keep GQA KV
    # replication when TP exceeds KV heads; do not divide all memory by TP*PP.
    rank_bytes = try(ceil((
      local.pp_weights / tp * min(1, (ceil(local.a.layers / pp) + 1) / local.a.layers) +
      local.pp_cache * min(1, (ceil(local.a.layers / pp) + 1) / local.a.layers) * max(1, ceil(local.a.kv_heads / tp)) / local.a.kv_heads +
      local.pp_embedding_bytes / tp
    ) * local.pp_payload_scale + local.profile.memory.runtime_allowance_bytes), null)
  } if try(tp <= row.shape.gpus && local.a.heads % tp == 0 && (local.a.kv_heads % tp == 0 || tp % local.a.kv_heads == 0) && pp <= local.a.layers && row.capacity.available_instances >= pp * var.replicas && row.entitled_instances >= pp * var.replicas, false)]]])
  pp_fits = [for layout in local.pp_layouts : layout if try(layout.rank_bytes <= layout.row.gpu.memory_bytes_per_gpu * 0.9, false)]
  # Keep the smallest feasible host group for each TP/shape/AD, not every larger
  # equivalent allocation. Replica groups use distinct complete host sets.
  pp_fit_groups = { for layout in local.pp_fits : jsonencode([layout.row.region, layout.row.ad, layout.row.shape.shape, layout.tp]) => layout... }
  packed_pp_rows = [for group in values(local.pp_fit_groups) : merge(group[0].row, {
    tp_options        = [group[0].tp], pp = group[0].pp, rank_bytes = group[0].rank_bytes,
    replicas_per_node = 1, node_count = group[0].pp * var.replicas, replicas = var.replicas
  })]
}
