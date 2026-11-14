# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { http = { source = "hashicorp/http", version = "~> 3.4" } }
}

locals {
  engines                 = var.engines
  catalog                 = jsondecode(var.gpu_catalog == null ? jsonencode(jsondecode(file("${path.module}/../accelerator-inventory/data/gpus.json")).shapes) : jsonencode(var.gpu_catalog))
  compute_cluster_regions = jsondecode(file("${path.module}/../accelerator-inventory/data/gpus.json")).compute_cluster_regions
  profile                 = var.profile
  a                       = try(local.profile.architecture.attention, { layers = 0, heads = 0, kv_heads = 0, hidden_size = 0, vocab_size = 0 })
  memory_supported        = try(local.profile.memory.status == "estimated" && local.a.layers > 0 && local.a.heads > 0 && local.a.kv_heads > 0 && local.a.hidden_size > 0 && local.a.vocab_size > 0, false)
  hints                   = try(local.profile.serving_requirements.version_hints, [])
  # Numeric comparison is restricted to stable X.Y.Z versions. Other expressions stay unknown.
  engine_checks = [for engine in local.engines : {
    engine          = engine
    architecture_ok = anytrue([for arch in try(local.profile.architecture.architectures, []) : contains(engine.architectures, arch)])
    hints_ok = alltrue([for hint in local.hints : try(
      hint.engine != engine.framework ? true : (
        length(regexall("^[0-9]+\\.[0-9]+\\.[0-9]+$", hint.version)) == 0 ? false :
        lookup({
          ">=" = sum([for i, n in split(".", engine.version) : tonumber(n) * pow(1000000, 2 - i)]) >= sum([for i, n in split(".", hint.version) : tonumber(n) * pow(1000000, 2 - i)])
          ">"  = sum([for i, n in split(".", engine.version) : tonumber(n) * pow(1000000, 2 - i)]) > sum([for i, n in split(".", hint.version) : tonumber(n) * pow(1000000, 2 - i)])
          "<=" = sum([for i, n in split(".", engine.version) : tonumber(n) * pow(1000000, 2 - i)]) <= sum([for i, n in split(".", hint.version) : tonumber(n) * pow(1000000, 2 - i)])
          "<"  = sum([for i, n in split(".", engine.version) : tonumber(n) * pow(1000000, 2 - i)]) < sum([for i, n in split(".", hint.version) : tonumber(n) * pow(1000000, 2 - i)])
          "==" = engine.version == hint.version
          "="  = engine.version == hint.version
        }, hint.operator, false)
      ), false)
    ])
  }]
  usable_engines = [for check in local.engine_checks : check.engine if check.architecture_ok && check.hints_ok]
  blocking_reasons = compact(concat(
    [local.memory_supported ? "" : "Model memory/layout estimator unsupported: ${join("; ", try(local.profile.memory.reasons, []))}"],
    [anytrue([for check in local.engine_checks : check.architecture_ok]) ? "" : "No reviewed engine supports the declared architecture: ${join(", ", try(local.profile.architecture.architectures, []))}. This is a catalog coverage limit, not proof the upstream engine cannot serve it."],
    [length(local.usable_engines) > 0 || !anytrue([for check in local.engine_checks : check.architecture_ok]) ? "" : "No architecture-compatible engine satisfies the extracted version hints."],
    [try(local.profile.model.pipeline_tag == "text-generation" && local.profile.model.chat_template_available, false) ? "" : "The initial recipe requires text generation and a declared chat template."]
  ))
  shape_rows = flatten([for region in var.regions : [for ad in region.inventory.availability_domains : [for shape in ad.shapes : {
    region               = region.inventory.region, ad = ad.name, shape = shape
    gpu                  = try(local.catalog[shape.shape], null)
    capacity_observed_at = try(one([for observation in region.capacity.availability_domains : observation.assessment.observed_at if observation.name == ad.name]), null)
    capacity             = try(one(flatten([for observation in region.capacity.availability_domains : [for row in observation.assessment.shapes : row if row.shape == shape.shape] if observation.name == ad.name])), null)
    headroom             = [for limit in region.inventory.limits : limit if contains(shape.quota_names, limit.name) && (limit.scope_type != "AD" || limit.availability_domain == ad.name)]
  }]]])
  layouts = flatten([for row in local.quantity_observations : [for engine in local.usable_engines : [for tp in [1, 2, 4, 8] : [for pp in range(1, var.max_nodes_per_replica + 1) : {
    row = row, engine = merge(engine, {
      image    = local.resolution_present ? try(engine.available_images["linux/${row.gpu.cpu_architecture}"], engine.platform == "linux/${row.gpu.cpu_architecture}" ? engine.image : null, null) : engine.image,
      platform = local.resolution_present ? try("linux/${row.gpu.cpu_architecture}", engine.platform) : try(engine.platform, null)
    }), tp     = tp, pp = pp
    # Do not infer cross-node placement of several PP replica groups.
    replicas_per_node = pp == 1 ? max(1, floor(row.shape.gpus / tp)) : 1
    # TP stays inside one host; PP spans hosts. Extra embedding allowance is conservative.
    rank_bytes = local.memory_supported ? ceil((
      local.profile.memory.weight_bytes / tp * min(local.a.layers, ceil(local.a.layers / pp) + (pp > 1 ? 1 : 0)) / local.a.layers +
      (tp * pp == 1 ? 0 : 2 * local.a.vocab_size * local.a.hidden_size * max([for dtype in keys(local.profile.weights.elements_by_dtype) : lookup({ F64 = 8, F32 = 4, F16 = 2, BF16 = 2 }, dtype, 8)]...) * (lookup(local.profile.memory.assumptions, "kv_dtype", "bfloat16") == "float32" ? 2 : 1)) +
      local.profile.memory.kv_bytes * min(local.a.layers, ceil(local.a.layers / pp) + (pp > 1 ? 1 : 0)) / local.a.layers * max(1, ceil(local.a.kv_heads / tp)) / local.a.kv_heads +
      local.profile.memory.runtime_allowance_bytes
    ) * (1 + local.profile.memory.assumptions.safety_margin_fraction)) : null
    reasons = compact([
      try(local.profile.model.pipeline_tag == "text-generation" && local.profile.model.chat_template_available, false) ? "" : "The initial serving recipe requires text generation and a declared chat template.",
      local.memory_supported ? "" : "Memory estimator or layout dimensions unsupported.",
      !local.resolution_present || try(engine.available_images["linux/${row.gpu.cpu_architecture}"] != null, engine.platform == "linux/${row.gpu.cpu_architecture}", false) ? "" : "No assessed image for this GPU node CPU platform.",
      try(row.gpu.gpus == row.shape.gpus, false) ? "" : "GPU catalog missing or GPU count disagrees with OCI.",
      try(contains(engine.gpu_compute_capabilities, row.gpu.compute_capability), false) ? "" : "Engine/GPU architecture is not covered by the catalog.",
      try(tp <= row.shape.gpus && local.a.heads % tp == 0 && (local.a.kv_heads % tp == 0 || tp % local.a.kv_heads == 0) && pp <= local.a.layers, false) ? "" : "Unsupported TP/PP attention partition.",
      pp == 1 || try(engine.multi_node_backend == "mp", false) ? "" : "Engine catalog does not establish native multi-node multiprocessing support.",
    ])
  }]]]])
  packed_layouts = [for layout in local.layouts : merge(layout, {
    node_count = layout.pp * ceil(var.replicas / layout.replicas_per_node)
    replicas   = ceil(var.replicas / layout.replicas_per_node) * layout.replicas_per_node
  })]
  evaluated = [for layout in local.packed_layouts : merge(layout, {
    memory_fit  = try(layout.rank_bytes <= layout.row.gpu.memory_bytes_per_gpu * 0.9, false)
    capacity_ok = try(layout.row.capacity.availability_status == "AVAILABLE" && layout.row.capacity.available_instances >= layout.node_count, false)
    # Quota names can have units such as GPUs/cores. Positive headroom alone is not a quantity proof.
    entitlement = try(layout.row.limit_status == "positive" && layout.row.entitled_instances >= layout.node_count, false) ? "confirmed_for_quantity" : "not_confirmed_for_quantity"
  })]
  raw_candidates = [for layout in local.evaluated : {
    id                         = substr(sha256(jsonencode([local.profile.model, local.profile.memory.assumptions, layout.row.region, layout.row.ad, layout.row.shape.shape, layout.engine.image, layout.tp, layout.pp, var.replicas, var.serving_resolution])), 0, 16)
    region                     = layout.row.region, availability_domain = layout.row.ad, gpu_shape = layout.row.shape.shape
    gpus_per_node              = layout.row.shape.gpus, node_count = layout.node_count, replicas = layout.replicas
    requested_minimum_replicas = var.replicas, replicas_per_node = layout.replicas_per_node
    tensor_parallel_size       = layout.tp, pipeline_parallel_size = layout.pp
    engine                     = layout.engine
    estimated_rank_bytes       = layout.rank_bytes
    gpu_memory_bytes           = layout.row.gpu.memory_bytes_per_gpu
    available_instances        = layout.row.capacity.available_instances
    capacity_observed_at       = try(one([for region in var.regions : one([for ad in region.capacity.availability_domains : ad.assessment.observed_at if ad.name == layout.row.ad]) if region.capacity.region == layout.row.region]), null)
    entitlement                = layout.entitlement
    requires_rdma              = layout.pp > 1 && try(layout.row.gpu.compute_cluster_supported && contains(local.compute_cluster_regions, layout.row.region) && layout.row.shape.rdma_ports > 0, false)
    status                     = "estimated_feasible_requires_validation"
    runtime_validation         = "not_run"
    configuration_status = !local.resolution_present ? "analytical_estimate_requires_validation" : try(
      var.serving_resolution.status == "resolved_requires_validation" &&
      contains(local.tested_hardware, layout.row.gpu.recipe_hardware) &&
      layout.row.gpu.recipe_hardware == var.serving_resolution.recipe.selected_hardware &&
      "linux/${layout.row.gpu.cpu_architecture}" == layout.engine.platform &&
      contains(var.serving_resolution.recipe.compatible_strategies, "single_node_tp") &&
      layout.pp == 1 && layout.tp == coalesce(try(tonumber(var.serving_resolution.recipe.variant_metadata.tp), null), try(tonumber(var.serving_resolution.recipe.strategy_overrides.single_node_tp.tp), null), try(tonumber(var.serving_resolution.recipe.strategy_overrides.single_node_tp.tp[layout.row.gpu.recipe_hardware]), null)), false
    ) ? "recipe_configuration_requires_validation" : "undetermined_requires_expert"
    recipe_hardware_status = contains(local.tested_hardware, try(layout.row.gpu.recipe_hardware, "unknown")) ? "upstream_hardware_match_only" : "no_tested_recipe_for_this_hardware"
    remaining_checks       = ["Recheck quantity-specific quota/entitlement.", "Confirm OKE image driver/CUDA compatibility and per-rank memory at runtime.", "Validate requested APIs and workload performance; Ethernet PP has no RDMA performance claim."]
  } if length(layout.reasons) == 0 && layout.memory_fit && layout.capacity_ok && layout.entitlement == "confirmed_for_quantity"]
}

output "assessment" {
  value = {
    schema_version                 = "1.0"
    control_plane                  = module.control_plane.requirements
    candidates                     = local.candidates
    status                         = length(local.suggestions) > 0 ? "suggestions_available" : length(local.candidates) > 0 ? "candidates_found" : length(local.sizing_options) > 0 ? "expert_options_available" : "requires_validation"
    recommended_selection_id       = try(local.ranked_suggestions[0].id, null)
    suggestions                    = local.ranked_suggestions
    recipe_options                 = { features = try(local.api.features, {}), kv_offload_support = try(local.api.kv_offload_support, {}), cache_options = local.cache_options, source = try(local.api.source, {}) }
    recipe_alternatives            = try(local.api.variants, {})
    recipe_api_diagnostics         = { for k, r in local.renderings : k => r.selection if !contains(keys(local.valid_renderings), k) }
    platform_policy                = { monitoring_enabled = var.monitoring_enabled, autoscaling_enabled = var.autoscaling_enabled, fixed_replica_packing = "fill_complete_replicas_on_allocated_single_node_hosts" }
    sizing_options                 = local.sizing_options
    sizing_diagnostics             = local.sizing_diagnostics
    recipe_hardware_targets        = local.recipe_targets
    serving_configuration_status   = try(var.serving_resolution.status, "explicit_engine_evidence")
    engine_checks                  = [for check in local.engine_checks : { engine = check.engine.id, architecture_supported = check.architecture_ok, version_hints_satisfied = check.hints_ok }]
    shape_observations             = [for row in local.availability_observations : merge(row, { catalog_known = try(local.catalog[row.shape], null) != null })]
    capacity_and_headroom_shapes   = local.capacity_and_headroom_shapes
    limit_increase_recommendations = local.limit_increase_recommendations
    blocking_reasons               = local.blocking_reasons
    evaluated_layout_count         = length(local.evaluated)
    rejection_counts = {
      layout_or_catalog = length([for layout in local.evaluated : true if length(layout.reasons) > 0])
      memory            = length([for layout in local.evaluated : true if !layout.memory_fit])
      capacity          = length([for layout in local.evaluated : true if !layout.capacity_ok])
      entitlement_zero  = length([for layout in local.evaluated : true if layout.entitlement != "confirmed_for_quantity"])
    }
    prompt_path = "outputs/model-compatibility-assessment-prompt.md"
    warnings    = ["Per-rank values are analytical estimates, including an extra embedding allowance; not load-test evidence.", "Quota units are not assumed to be instances. Selectable options require quantity-specific GPU headroom for the complete shape allocation.", "Shapes may share host inventory. Candidates are alternatives; capacity counts are never summed.", "Resolved image references use immutable digests; hardware and serving validation remain required."]
  }
}
