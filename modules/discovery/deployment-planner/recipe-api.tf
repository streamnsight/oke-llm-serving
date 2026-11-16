# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  recipe_id = try(local.profile.model.repository, "")
}
data "http" "recipe_metadata" {
  count              = var.recipe_api_enabled && var.recipe_metadata == null ? 1 : 0
  url                = "https://recipes.vllm.ai/${local.recipe_id}.json"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = contains([200, 404], self.status_code)
      error_message = "Recipe API metadata lookup failed; only 404 means absent."
    }
  }
}
locals {
  api                  = jsondecode(var.recipe_metadata != null ? jsonencode(var.recipe_metadata.body) : try(data.http.recipe_metadata[0].response_body, "{}"))
  api_variants         = [for name, v in try(local.api.variants, {}) : name if try(v.model_id, local.api.model.model_id, "") == try(local.profile.model.repository, "unknown")]
  api_variant          = try(local.api.recommended_command.variant, contains(local.api_variants, "default") ? "default" : one(local.api_variants), null)
  api_variant_metadata = try(local.api.variants[local.api_variant], {})
  # A10 is absent from the API taxonomy. Adapt only the portable BF16 baseline,
  # never a quantized profile whose kernels may require a different architecture.
  api_targets = { for row in local.sizing_rows : row.hardware => lookup({ a10 = "h100", "a100-40gb" = "h100", "a100-80gb" = "h100", l40s = "h100", "rtx-pro-6000-blackwell" = "rtx_pro_6000" }, row.hardware, row.hardware)... if var.recipe_api_enabled && local.api_variant != null && try(
    row.gpu.compute_capability >= 80 && row.capacity_status == "positive" && row.capacity.available_instances >= 1 && row.limit_status == "positive" && row.entitled_instances >= 1, false
  ) }
  api_hardware      = { for hardware, targets in local.api_targets : hardware => targets[0] if !contains(["a10", "a100-40gb", "a100-80gb", "l40s"], hardware) || try(local.api_variant_metadata.precision == "bf16", false) }
  rendering_queries = { for hardware, target in local.api_hardware : hardware => "hardware=${urlencode(target)}&variant=${urlencode(local.api_variant)}&strategy=single_node_tp" }
}
data "http" "recipe_rendering" {
  for_each           = toset(values(local.rendering_queries))
  url                = "https://recipes.vllm.ai/${local.recipe_id}.json?${each.key}"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = contains([200, 404], self.status_code)
      error_message = "Recipe configuration lookup failed."
    }
  }
}
locals {
  renderings       = { for hardware, query in local.rendering_queries : hardware => jsondecode(data.http.recipe_rendering[query].response_body) if data.http.recipe_rendering[query].status_code == 200 }
  valid_renderings = { for hardware, r in local.renderings : hardware => r if try(r.selection.hardware == local.api_hardware[hardware] && r.selection.variant == local.api_variant && r.selection.strategy == "single_node_tp" && length(r.selection.adjusted) == 0 && r.argv[0] == "vllm" && r.argv[1] == "serve" && r.argv[2] == local.profile.model.repository, false) }
  rendering_images = toset([for r in values(local.valid_renderings) : r.docker_image if can(regex("^vllm/vllm-openai:[A-Za-z0-9_.-]+$", r.docker_image))])
  resolved_recipe_images = { for image in local.rendering_images : image => var.serving_resolution.engine.available_images if try(
    image == "vllm/vllm-openai:${var.serving_resolution.engine.image_tag}" && length(var.serving_resolution.engine.available_images) > 0 &&
    alltrue([for reference in values(var.serving_resolution.engine.available_images) : can(regex("^vllm/vllm-openai@sha256:[a-f0-9]{64}$", reference))]), false
  ) }
  api_images = setsubtract(local.rendering_images, toset(keys(local.resolved_recipe_images)))
}
data "http" "recipe_image" {
  for_each           = local.api_images
  url                = "https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags/${split(":", each.value)[1]}"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = contains([200, 404], self.status_code)
      error_message = "Recipe image metadata lookup failed."
    }
  }
}
locals {
  recipe_images = merge(local.resolved_recipe_images, { for image, response in data.http.recipe_image : image => { for platform in ["amd64", "arm64"] : "linux/${platform}" => "vllm/vllm-openai@${one([for i in try(jsondecode(response.response_body).images, []) : i.digest if i.os == "linux" && i.architecture == platform])}" if length([for i in try(jsondecode(response.response_body).images, []) : i if i.os == "linux" && i.architecture == platform && can(regex("^sha256:[a-f0-9]{64}$", i.digest))]) == 1 } })
  # Recipe guidelines are a heuristic budget, not a per-rank allocation proof.
  heuristic_weights = try(local.api_variant_metadata.precision == "bf16" && local.profile.weights.tensor_data_bytes > 0 ? max(local.profile.weights.tensor_data_bytes, local.profile.weights.tensor_elements * (local.profile.memory.assumptions.kv_dtype == "float32" ? 4 : 2)) : null, null)
  heuristic_kv = try(local.heuristic_weights > 0 && alltrue([for n in [local.a.layers, local.a.kv_heads, local.a.head_dim] : n > 0]) ?
  2 * local.a.layers * local.a.kv_heads * local.a.head_dim * (local.profile.memory.assumptions.kv_dtype == "float32" ? 4 : 2) * local.profile.memory.assumptions.context_length * local.profile.memory.assumptions.concurrency : null, null)
  heuristic_payload = try((local.heuristic_weights + local.heuristic_kv) * (1 + try(local.profile.memory.assumptions.safety_margin_fraction, 0.2)), null)
  api_budget        = try(max(local.api_variant_metadata.vram_minimum_gb * 1e9, coalesce(local.payload_estimate, 0), coalesce(local.heuristic_payload, 0)), null)
  memory_budget_breakdown = {
    weight_bytes                    = local.heuristic_weights, kv_surrogate_bytes = local.heuristic_kv,
    safety_margin_fraction          = try(local.profile.memory.assumptions.safety_margin_fraction, 0.2),
    recipe_minimum_bytes            = try(local.api_variant_metadata.vram_minimum_gb * 1e9, null),
    analytical_or_fallback_bytes    = local.payload_estimate, heuristic_payload_bytes = local.heuristic_payload,
    selected_payload_budget_bytes   = local.api_budget,
    runtime_allowance_per_gpu_bytes = try(local.profile.memory.runtime_allowance_bytes, null),
    status                          = "heuristic_requires_runtime_validation"
  }
  suggestion_rows = [for row in local.sizing_rows : merge(row, {
    rendering  = local.valid_renderings[row.hardware]
    image      = local.recipe_images[local.valid_renderings[row.hardware].docker_image][row.platform]
    tp_options = [for tp in [1, 2, 4, 8] : tp if try(local.api_budget > 0 && try(local.profile.memory.assumptions.context_length <= local.api.model.context_length, true) && row.gpu.gpus == row.shape.gpus && tp <= row.shape.gpus && local.a.heads % tp == 0 && (local.a.kv_heads % tp == 0 || tp % local.a.kv_heads == 0) && local.api_budget / tp + local.profile.memory.runtime_allowance_bytes <= row.gpu.memory_bytes_per_gpu * 0.9, false)]
  }) if can(local.valid_renderings[row.hardware]) && can(local.recipe_images[local.valid_renderings[row.hardware].docker_image][row.platform])]
  packed_suggestion_rows = [for row in local.suggestion_rows : merge(row, {
    replicas_per_node = floor(row.shape.gpus / row.tp_options[0])
    node_count        = ceil(var.replicas / floor(row.shape.gpus / row.tp_options[0]))
    replicas          = ceil(var.replicas / floor(row.shape.gpus / row.tp_options[0])) * floor(row.shape.gpus / row.tp_options[0])
  }) if length(row.tp_options) > 0]
  raw_suggestions = [for row in local.packed_suggestion_rows : {
    id                         = substr(sha256(jsonencode([local.profile.model, local.profile.memory.assumptions, row.region, row.ad, row.shape.shape, row.rendering, row.image, "recipe-suggestion"])), 0, 16)
    region                     = row.region, availability_domain = row.ad, gpu_shape = row.shape.shape, gpus_per_node = row.shape.gpus
    tensor_parallel_size       = row.tp_options[0], pipeline_parallel_size = 1, node_count = row.node_count, replicas = row.replicas, requires_rdma = false
    requested_minimum_replicas = var.replicas, replicas_per_node = row.replicas_per_node
    configuration_status       = "suggested_requires_validation", configuration_origin = row.hardware == local.api_hardware[row.hardware] && tostring(row.tp_options[0]) == try(row.rendering.argv[index(row.rendering.argv, "--tensor-parallel-size") + 1], "") ? "upstream_rendering" : "adapted_recipe"
    runtime_validation         = "not_run", upstream_validation = "not_established_for_this_configuration"
    deployment_requirements    = try(local.profile.model.config_sources.config_repository != null, false) ? ["Stage the independently pinned external config/tokenizer before deployment; the weights revision must not be reused as the config repository revision."] : []
    estimated_rank_bytes       = ceil(local.api_budget / row.tp_options[0] + local.profile.memory.runtime_allowance_bytes)
    memory_status              = "heuristic_recipe_budget_not_per_rank_proof", aggregate_payload_bytes = local.api_budget
    capacity_status            = row.capacity_status, limit_status = row.limit_status, headroom_status = row.headroom_status
    available_instances        = try(row.capacity.available_instances, null)
    availability               = "available_at_scan"
    entitled_instances         = row.entitled_instances
    capacity_observed_at       = row.capacity_observed_at
    serving_configuration = {
      deployment_profile = try(row.rendering.deployment_profile, var.serving_resolution.deployment_profile, {})
      status             = "suggested_requires_validation", model = local.profile.model
      engine             = merge(var.serving_resolution.engine, { id = "recipe-${row.hardware}", image = row.image, platform = row.platform, available_images = local.recipe_images[row.rendering.docker_image], image_tag = row.rendering.docker_image, version = "recipe-${split(":", row.rendering.docker_image)[1]}", channel = "recipe", image_source_association = "recipe_image_digest_runtime_not_verified" })
      recipe = merge(var.serving_resolution.recipe, {
        args         = [for i, arg in slice(row.rendering.argv, 3, length(row.rendering.argv)) : arg if !contains(local.recipe_managed_flags, split("=", arg)[0]) && !try(contains(local.recipe_managed_flags, slice(row.rendering.argv, 3, length(row.rendering.argv))[i - 1]), false)]
        env          = row.rendering.env, selected_features = row.rendering.selection.features, selected_hardware = row.hardware
        api          = { url = data.http.recipe_rendering[local.rendering_queries[row.hardware]].url, sha256 = sha256(data.http.recipe_rendering[local.rendering_queries[row.hardware]].response_body), selection = row.rendering.selection, original_argv = row.rendering.argv, original_image = row.rendering.docker_image, rendering = row.rendering }
        dependencies = try(local.api.model.install.extras, []), companions = try(row.rendering.companions, [])
        serving_mode = try(local.api.meta.tasks[0], "unknown"), serving_tasks = try(local.api.meta.tasks, []), modality_validation = "not_run_requires_task_specific_validation"
      })
    }
    recommendation_reason = "Smallest enumerated intra-host TP layout meeting a heuristic memory budget; spare GPUs on allocated hosts run complete extra replicas. Full host quantities have confirmed capacity/headroom; no price or throughput prediction."
    warnings              = ["Untested configuration; run deployment validation and benchmarking.", "Memory budget divides upstream guidance approximately; sharding balance, recurrent/vision state, CUDA graphs and workload KV fit are not proven.", "Recipe dependency commands are evidence, not executed; validate their availability in the pinned image.", row.hardware == "a10" ? "A10 adapts the H100 BF16 baseline; TP may cross PCIe and is not upstream validated." : "GPU model match alone does not establish validation of this image/variant/TP/workload."]
  } if try(row.capacity_status == "positive" && row.capacity.available_instances >= row.node_count && row.limit_status == "positive" && row.entitled_instances >= row.node_count, false) && try(!contains(keys(local.api_variant_metadata), "supported_hardware") || contains(local.api_variant_metadata.supported_hardware, row.hardware), true)]
  recipe_managed_flags = ["--tensor-parallel-size", "-tp", "--pipeline-parallel-size", "-pp", "--max-model-len", "--max-num-seqs", "--dtype", "--kv-cache-dtype", "--gpu-memory-utilization"]
}


# Companion services need Kubernetes resource/memory configuration. Retain their
# complete API plans for review without silently enabling a second process.
locals {
  cache_queries = { for pair in setproduct(keys(local.valid_renderings), ["simple", "lmcache"]) : "${pair[0]}/${pair[1]}" => "${local.rendering_queries[pair[0]]}&kv_offload=${urlencode(pair[1])}" if var.assess_cache_alternatives && try(local.api.kv_offload_support.offloading_cpu != "unsupported", false) }
}
data "http" "cache_option" {
  for_each           = toset(values(local.cache_queries))
  url                = "https://recipes.vllm.ai/${local.recipe_id}.json?${each.key}"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = contains([200, 404], self.status_code)
      error_message = "Recipe KV-cache option lookup failed."
    }
  }
}
locals {
  cache_options = { for key, query in local.cache_queries : key => {
    configuration_status = "requires_cache_integration", source_url = data.http.cache_option[query].url, sha256 = sha256(data.http.cache_option[query].response_body)
    plan                 = jsondecode(data.http.cache_option[query].response_body)
    remaining_checks     = ["Configure Kubernetes companion processes, readiness and shared transport.", "Size host cache memory against the selected OCI shape; recipe defaults are not allocation recommendations."]
  } if data.http.cache_option[query].status_code == 200 }
}
