# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  image_override      = try(length(trimspace(var.engine_image)) > 0, false) ? trimspace(var.engine_image) : null
  version_override    = try(length(trimspace(var.engine_version)) > 0, false) ? trimspace(var.engine_version) : null
  selection_key       = try(length(trimspace(var.selection_id)) > 0, false) ? trimspace(var.selection_id) : null
  discovery_document  = var.discovery_json != null ? jsondecode(var.discovery_json) : var.discovery
  discovery_input     = try(local.discovery_document.discovery, local.discovery_document)
  choices             = concat(try(local.discovery_input.assessment.suggestions, []), try(local.discovery_input.assessment.candidates, []), try(local.discovery_input.assessment.sizing_options, []))
  choice_matches      = [for c in local.choices : c if local.selection_key == null ? length(local.choices) == 1 : c.id == local.selection_key]
  selected            = try(one(local.choice_matches), null)
  suggested           = try(local.selected.configuration_status == "suggested_requires_validation", false)
  resolution          = jsondecode(var.serving_configuration != null ? jsonencode(var.serving_configuration) : jsonencode(try(local.selected.serving_configuration, local.discovery_input.serving_configuration, null)))
  assessed_engines    = try(local.resolution.engine_candidates, [local.resolution.engine], [])
  matching_engines    = [for e in local.assessed_engines : e if try(local.version_override != null && local.image_override == null ? e.version == local.version_override : var.engine_channel == "recommended" ? e.id == local.resolution.engine.id : try(e.channel, e.version == "nightly" ? "nightly" : "stable") == var.engine_channel, false)]
  assessed_engine     = length(local.matching_engines) == 1 ? local.matching_engines[0] : try(local.resolution.engine, null)
  region              = try(local.selected.region, var.region)
  availability_domain = try(local.selected.availability_domain, var.availability_domain)
  gpu_shape           = try(local.selected.gpu_shape, var.gpu_shape)
  node_count          = try(coalesce(var.node_count, try(local.selected.node_count, null)), null)
  tp                  = try(coalesce(var.tensor_parallel_size, try(local.selected.tensor_parallel_size, null)), null)
  pp                  = try(coalesce(var.pipeline_parallel_size, try(local.selected.pipeline_parallel_size, null)), null)
  replicas            = coalesce(var.replicas, try(local.selected.replicas, null), 1)
  requires_rdma       = coalesce(var.requires_rdma, try(local.selected.requires_rdma, null), false)
  model               = try(coalesce(var.model, try(local.discovery_input.profile.model.repository, null)), null)
  model_revision      = try(coalesce(var.model_revision, try(local.discovery_input.profile.model.resolved_revision, null)), null)
  context_length      = coalesce(var.context_length, try(local.discovery_input.profile.memory.assumptions.context_length, null), 4096)
  concurrency         = coalesce(var.concurrency, try(local.discovery_input.profile.memory.assumptions.concurrency, null), 1)
  kv_dtype            = coalesce(var.kv_dtype, try(local.discovery_input.profile.memory.assumptions.kv_dtype, null), "bfloat16")
  runtime_gib         = coalesce(var.runtime_gib, try(local.discovery_input.profile.memory.assumptions.runtime_allowance_gib, null), 2)
  margin              = coalesce(var.margin, try(local.discovery_input.profile.memory.assumptions.safety_margin_fraction, null), 0.2)
  observation_id      = coalesce(var.observation_id, "allocation-${try(local.discovery_input.observation_id, "manual")}-${coalesce(local.selection_key, "manual")}")
  assessment_id       = coalesce(var.assessment_id, try(local.selected.id, null), "manual")
  engine_platform     = var.engine_platform == "auto" ? try("linux/${local.gpu.cpu_architecture}", try(local.assessed_engine.platform, "linux/amd64")) : var.engine_platform
  resolved_engine = merge({ id = "unresolved", framework = "vllm", architectures = [], gpu_compute_capabilities = [], multi_node_backend = null }, jsondecode(local.assessed_engine == null ? "{}" : jsonencode(local.assessed_engine)), {
    image                    = try(local.image_override != null ? local.image_override : try(local.assessed_engine.available_images[local.engine_platform], local.assessed_engine.platform == local.engine_platform ? local.assessed_engine.image : null), null),
    version                  = try(coalesce(local.version_override, try(local.assessed_engine.version, null)), "unresolved"), platform = local.engine_platform,
    image_source_association = local.image_override != null ? "deployment_override_not_verified" : try(local.assessed_engine.image_source_association, "assessed")
  })
  engine_image    = try(coalesce(local.image_override, local.engine.image), null)
  engine_version  = try(coalesce(local.version_override, local.engine.version), null)
  feature_options = try(local.resolution.recipe.feature_options, {})
  feature_args    = flatten([for name in sort(tolist(setsubtract(var.recipe_features, toset(try(local.resolution.recipe.selected_features, []))))) : try(local.feature_options[name].hardware_overrides[local.gpu.recipe_hardware].args, local.feature_options[name].args, [])])
  feature_env     = merge({}, [for name in sort(tolist(setsubtract(var.recipe_features, toset(try(local.resolution.recipe.selected_features, []))))) : merge(try(local.feature_options[name].env, {}), try(local.feature_options[name].hardware_overrides[local.gpu.recipe_hardware].env, {}))]...)
  serving_configuration = local.resolution == null ? null : merge(local.resolution, {
    engine = local.engine,
    recipe = merge(local.resolution.recipe, {
      selected_features = distinct(concat(try(local.resolution.recipe.selected_features, []), sort(tolist(var.recipe_features)))),
      args              = concat(try(local.resolution.recipe.args, []), local.feature_args),
      env               = merge(try(local.resolution.recipe.env, {}), local.feature_env)
    })
  })
}
