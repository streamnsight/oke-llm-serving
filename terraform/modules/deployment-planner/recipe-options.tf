# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  resolution_present = var.serving_resolution != null
  recipe_hardware    = try(var.serving_resolution.recipe.hardware, {})
  tested_hardware    = [for name, status in local.recipe_hardware : name if status == "verified"]
  # This is deliberately not a per-rank estimator or an executable layout.
  # Flint declares only ordinary full/sliding GQA, so full-context payload on every
  # layer supplies a conservative KV payload bound; scratch/placement stay unknown.
  fallback_payload_known = try(
    local.profile.architecture.model_type == "flint" && local.profile.architecture.quantization == null &&
    local.profile.weights.selected_checkpoint != null && local.profile.weights.tensor_data_bytes > 0 &&
    local.profile.weights.tensor_elements > 0 &&
    length(local.a.layer_types) == local.a.layers &&
    alltrue([for t in local.a.layer_types : contains(["full_attention", "sliding_attention"], t)]) &&
    alltrue([for n in [local.a.layers, local.a.heads, local.a.kv_heads, local.a.head_dim] : n > 0]) &&
  local.a.heads % local.a.kv_heads == 0, false)
  payload_estimate = local.memory_supported ? try(local.profile.memory.recommended_aggregate_bytes, ceil((local.profile.memory.weight_bytes + local.profile.memory.kv_bytes + local.profile.memory.runtime_allowance_bytes) * (1 + local.profile.memory.assumptions.safety_margin_fraction))) : local.fallback_payload_known ? ceil((
    max(local.profile.weights.tensor_data_bytes, local.profile.weights.tensor_elements * (local.profile.memory.assumptions.kv_dtype == "float32" ? 4 : 2)) +
    2 * local.a.layers * local.a.kv_heads * local.a.head_dim * (local.profile.memory.assumptions.kv_dtype == "float32" ? 4 : 2) * local.profile.memory.assumptions.context_length * local.profile.memory.assumptions.concurrency +
    local.profile.memory.runtime_allowance_bytes
  ) * (1 + local.profile.memory.assumptions.safety_margin_fraction)) : null
  sizing_rows = [for row in local.quota_observations : merge(row, {
    hardware      = try(row.gpu.recipe_hardware, "unknown")
    platform      = try("linux/${row.gpu.cpu_architecture}", "unknown")
    minimum_gpus  = try(ceil(local.payload_estimate / (row.gpu.memory_bytes_per_gpu * 0.9)), null)
    minimum_nodes = try(ceil(ceil(local.payload_estimate / (row.gpu.memory_bytes_per_gpu * 0.9)) / row.shape.gpus), null)
  }) if local.resolution_present && try(row.gpu.memory_bytes_per_gpu > 0 && row.gpu.compute_capability >= (local.profile.memory.assumptions.kv_dtype == "bfloat16" ? 80 : 75), false)]
  sizing_options = [for row in local.sizing_rows : {
    id                                      = substr(sha256(jsonencode([local.profile.model, local.profile.memory.assumptions, var.serving_resolution, row.region, row.ad, row.shape.shape, "payload-only"])), 0, 16)
    region                                  = row.region, availability_domain = row.ad, gpu_shape = row.shape.shape, gpus_per_node = row.shape.gpus
    estimated_minimum_gpus                  = row.minimum_gpus, estimated_minimum_nodes = row.minimum_nodes, aggregate_payload_bytes = local.payload_estimate
    memory_status                           = local.payload_estimate != null ? "payload_only_not_per_rank_fit" : "unknown_requires_expert_estimate"
    configuration_status                    = "undetermined_requires_expert", runtime_validation = "not_run"
    recipe_hardware_status                  = contains(local.tested_hardware, row.hardware) ? "upstream_hardware_match_only" : "no_tested_recipe_for_this_hardware"
    recipe_hardware                         = row.hardware, image_platform = row.platform
    assessed_image_available                = try(var.serving_resolution.engine.available_images[row.platform] != null, row.platform == var.serving_resolution.engine.platform)
    capacity_status                         = row.capacity_status, limit_status = row.limit_status, headroom_status = row.headroom_status
    available_instances                     = try(row.capacity.available_instances, null)
    capacity_covers_estimated_minimum_nodes = try(row.capacity.available_instances >= row.minimum_nodes, false)
    requires_rdma                           = false
    remaining_checks                        = ["Expert must supply TP/PP, node count, per-rank memory bound and suitable args; aggregate sizing is not an executable configuration.", "No assumption that weights/KV divide evenly or that the model can use this many GPUs.", "Recheck quantity-specific capacity/limits, node CPU architecture, CUDA/driver compatibility, then validate and benchmark."]
  }]
  recipe_targets = [for shape, gpu in local.catalog : {
    gpu_shape    = shape, recipe_hardware = try(gpu.recipe_hardware, "unknown"), image_platform = try("linux/${gpu.cpu_architecture}", "unknown")
    observations = [for row in local.availability_observations : row if row.shape == shape]
    next_step    = anytrue([for row in local.availability_observations : row.limit_status == "zero" if row.shape == shape]) ? "Request the matching regional/AD GPU limit increase; entitlement is separate from capacity." : "Investigate capacity and entitlement for the upstream recipe hardware; absence from this scan is not global unavailability."
  } if contains(local.tested_hardware, try(gpu.recipe_hardware, "unknown"))]
}
