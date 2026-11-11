# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform { required_version = ">= 1.5.0" }

locals {
  engines                 = jsondecode(var.engines == null ? jsonencode(jsondecode(file("${path.module}/../../../catalogs/engines.json")).engines) : jsonencode(var.engines))
  catalog                 = jsondecode(var.gpu_catalog == null ? jsonencode(jsondecode(file("${path.module}/../../../catalogs/gpus.json")).shapes) : jsonencode(var.gpu_catalog))
  compute_cluster_regions = jsondecode(file("${path.module}/../../../catalogs/gpus.json")).compute_cluster_regions
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
    region   = region.inventory.region, ad = ad.name, shape = shape
    gpu      = try(local.catalog[shape.shape], null)
    capacity = try(one(flatten([for observation in region.capacity.availability_domains : [for row in observation.assessment.shapes : row if row.shape == shape.shape] if observation.name == ad.name])), null)
    headroom = [for limit in region.inventory.limits : limit if contains(shape.quota_names, limit.name) && (limit.scope_type != "AD" || limit.availability_domain == ad.name)]
  }]]])
  layouts = flatten([for row in local.quota_observations : [for engine in local.usable_engines : [for tp in [1, 2, 4, 8] : [for pp in range(1, var.max_nodes_per_replica + 1) : {
    row = row, engine = engine, tp = tp, pp = pp
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
      try(row.gpu.gpus == row.shape.gpus, false) ? "" : "GPU catalog missing or GPU count disagrees with OCI.",
      try(contains(engine.gpu_compute_capabilities, row.gpu.compute_capability), false) ? "" : "Engine/GPU architecture is not covered by the catalog.",
      try(tp <= row.shape.gpus && local.a.heads % tp == 0 && (local.a.kv_heads % tp == 0 || tp % local.a.kv_heads == 0) && pp <= local.a.layers, false) ? "" : "Unsupported TP/PP attention partition.",
      pp == 1 || try(engine.multi_node_backend == "mp", false) ? "" : "Engine catalog does not establish native multi-node multiprocessing support.",
    ])
  }]]]])
  evaluated = [for layout in local.layouts : merge(layout, {
    memory_fit  = try(layout.rank_bytes <= layout.row.gpu.memory_bytes_per_gpu * 0.9, false)
    capacity_ok = try(layout.row.capacity.availability_status == "AVAILABLE" && layout.row.capacity.available_instances >= layout.pp * var.replicas, false)
    # Quota names can have units such as GPUs/cores. Positive headroom alone is not a quantity proof.
    entitlement = layout.row.limit_status == "zero" || layout.row.headroom_status == "zero" ? "blocked" : layout.row.mapping_complete && layout.row.headroom_status == "positive" ? "positive_unconverted" : "unknown"
  })]
  candidates = [for layout in local.evaluated : {
    id                   = substr(sha256(jsonencode([local.profile.model, local.profile.memory.assumptions, layout.row.region, layout.row.ad, layout.row.shape.shape, layout.engine.image, layout.tp, layout.pp, var.replicas])), 0, 16)
    region               = layout.row.region, availability_domain = layout.row.ad, gpu_shape = layout.row.shape.shape
    gpus_per_node        = layout.row.shape.gpus, node_count = layout.pp * var.replicas, replicas = var.replicas
    tensor_parallel_size = layout.tp, pipeline_parallel_size = layout.pp
    engine               = layout.engine
    estimated_rank_bytes = layout.rank_bytes
    gpu_memory_bytes     = layout.row.gpu.memory_bytes_per_gpu
    available_instances  = layout.row.capacity.available_instances
    capacity_observed_at = try(one([for region in var.regions : one([for ad in region.capacity.availability_domains : ad.assessment.observed_at if ad.name == layout.row.ad]) if region.capacity.region == layout.row.region]), null)
    entitlement          = layout.entitlement
    requires_rdma        = layout.pp > 1 && try(layout.row.gpu.compute_cluster_supported && contains(local.compute_cluster_regions, layout.row.region) && layout.row.shape.rdma_ports > 0, false)
    status               = "estimated_feasible_requires_validation"
    runtime_validation   = "not_run"
    remaining_checks     = ["Recheck quantity-specific quota/entitlement.", "Confirm OKE image driver/CUDA compatibility and per-rank memory at runtime.", "Validate requested APIs and workload performance; Ethernet PP has no RDMA performance claim."]
  } if length(layout.reasons) == 0 && layout.memory_fit && layout.capacity_ok && layout.entitlement != "blocked"]
}

output "assessment" {
  value = {
    schema_version                 = "1.0"
    candidates                     = local.candidates
    status                         = length(local.candidates) > 0 ? "candidates_found" : "requires_validation"
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
      entitlement_zero  = length([for layout in local.evaluated : true if layout.entitlement == "blocked"])
    }
    prompt_path = "outputs/model-compatibility-assessment-prompt.md"
    warnings    = ["Per-rank values are analytical estimates, including an extra embedding allowance; not load-test evidence.", "Quota units are not assumed to be instances. Positive unconverted headroom requires quantity validation.", "Shapes may share host inventory. Candidates are alternatives; capacity counts are never summed.", "Engine selection precedes image pinning; all selected catalog images use immutable digests."]
  }
}
