# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform { required_version = ">= 1.5.0" }
locals {
  model_budget_bytes = try(coalesce(try(var.profile.memory.recommended_aggregate_bytes, null), try(var.assessment.recipe_options.memory_budget_bytes, null)), null)
  model_budget_basis = try(var.profile.memory.recommended_aggregate_bytes > 0, false) ? "analytical_aggregate_estimate" : local.model_budget_bytes != null ? "heuristic_recipe_budget" : "unknown"
  inventory_rows = flatten([for region in var.regions : [for ad in try(region.inventory.availability_domains, []) : [for shape in ad.shapes : {
    region          = region.inventory.region, ad = ad.name, shape = shape.shape, gpus = shape.gpus,
    gpu_description = try(shape.gpu_description, null), memory_bytes_per_gpu = try(shape.gpu_memory_bytes_per_gpu, null)
    limits          = [for limit in try(region.inventory.limits, []) : limit if contains(try(shape.quota_names, []), limit.name) && (limit.scope_type != "AD" || limit.availability_domain == ad.name)]
  }]]])
  capacity_rows = flatten([for region in var.regions : [for ad in try(region.capacity.availability_domains, []) : [for row in try(ad.assessment.shapes, []) : {
    region       = region.capacity.region, ad = ad.name, shape = row.shape,
    fault_domain = try(row.fault_domain, null), status = row.availability_status,
    hosts        = try(row.available_instances, null), observed_at = try(ad.assessment.observed_at, null)
  }]]])
  shape_keys = toset(concat(
    [for row in local.inventory_rows : jsonencode([row.region, row.shape])],
    [for row in local.capacity_rows : jsonencode([row.region, row.shape])],
    [for option in values(var.options) : jsonencode([option.region, option.gpu_shape])]
  ))
  shape_contexts = { for key in local.shape_keys : key => {
    region               = jsondecode(key)[0], shape = jsondecode(key)[1]
    memory_bytes_per_gpu = try(one(distinct([for row in local.inventory_rows : row.memory_bytes_per_gpu if row.region == jsondecode(key)[0] && row.shape == jsondecode(key)[1] && try(row.memory_bytes_per_gpu > 0, false)])), null)
    ads = sort(distinct(flatten([for region in var.regions : concat(
      [for ad in try(region.inventory.availability_domains, []) : ad.name],
      [for ad in try(region.capacity.availability_domains, []) : ad.name]
    ) if try(region.inventory.region, region.capacity.region) == jsondecode(key)[0]])))
    gpu_counts = distinct(concat(
      [for row in local.inventory_rows : row.gpus if row.region == jsondecode(key)[0] && row.shape == jsondecode(key)[1]],
      [for option in values(var.options) : option.gpus_per_node if try(option.region == jsondecode(key)[0] && option.gpu_shape == jsondecode(key)[1] && option.gpus_per_node > 0, false)]
    ))
  } }
  ad_contexts = merge({}, [for key, shape in local.shape_contexts : {
    for ad in shape.ads : jsonencode([shape.region, shape.shape, ad]) => {
      shape_key = key, ad = ad,
      rows      = distinct([for row in local.capacity_rows : row if row.region == shape.region && row.shape == shape.shape && row.ad == ad])
    }
  }]...)
  ad_checks = { for key, ad in local.ad_contexts : key => merge(ad, {
    known = try(length(ad.rows) == 1 && ad.rows[0].fault_domain == null && contains(["AVAILABLE", "OUT_OF_HOST_CAPACITY"], ad.rows[0].status) && (ad.rows[0].status == "OUT_OF_HOST_CAPACITY" || ad.rows[0].hosts >= 0), false)
  }) }
  ad_observations = { for key, ad in local.ad_checks : key => {
    shape_key       = ad.shape_key, availability_domain = ad.ad, known = ad.known,
    available_hosts = ad.known ? (ad.rows[0].status == "OUT_OF_HOST_CAPACITY" ? 0 : ad.rows[0].hosts) : null,
    status          = ad.known ? ad.rows[0].status : length(ad.rows) == 0 ? "not_assessed" : "ambiguous_or_incomplete_report",
    observed_at     = length(ad.rows) == 1 ? ad.rows[0].observed_at : null
  } }
  minimum_model_hosts = { for key, shape in local.shape_contexts : key => try(
    local.model_budget_bytes > 0 ? ceil(local.model_budget_bytes / (one(shape.gpu_counts) * shape.memory_bytes_per_gpu * 0.9)) : null, null
  ) }
  ad_limits = { for key, ad in local.ad_observations : key => distinct(flatten([
    for row in local.inventory_rows : row.limits if jsonencode([row.region, row.shape]) == ad.shape_key && row.ad == ad.availability_domain
  ])) }
  limit_requests = { for key, ad in local.ad_observations : key => [for limit in local.ad_limits[key] : {
    limit_name                   = limit.name, scope = limit.scope_type, availability_domain = limit.scope_type == "AD" ? ad.availability_domain : null,
    current_limit                = limit.tenancy_limit,
    minimum_gpus_for_whole_hosts = try(local.minimum_model_hosts[ad.shape_key] * one(local.shape_contexts[ad.shape_key].gpu_counts), null),
    model_fit                    = local.minimum_model_hosts[ad.shape_key] == null ? "unknown_validate_model_sizing_first" : "aggregate_memory_only_validate_layout_and_runtime"
    } if try(ad.known && ad.available_hosts > 0 &&
    (local.minimum_model_hosts[ad.shape_key] == null ? true : ad.available_hosts >= local.minimum_model_hosts[ad.shape_key]) &&
    (tonumber(limit.tenancy_limit) == 0 ? true : try(startswith(limit.description, "GPUs for ") && tonumber(limit.tenancy_limit) > 0 && tonumber(limit.tenancy_limit) < local.minimum_model_hosts[ad.shape_key] * one(local.shape_contexts[ad.shape_key].gpu_counts), false)), false)
  ] }
  ad_details = { for key, ad in local.ad_observations : key => merge(ad, {
    entitled_hosts      = try(one([for row in var.assessment.shape_observations : row.entitled_instances if jsonencode([row.region, row.shape]) == ad.shape_key && row.availability_domain == ad.availability_domain]), null),
    entitlement_status  = try(one([for row in var.assessment.shape_observations : row.status if jsonencode([row.region, row.shape]) == ad.shape_key && row.availability_domain == ad.availability_domain]), "unknown"),
    minimum_model_hosts = local.minimum_model_hosts[ad.shape_key], limit_increase_requests = local.limit_requests[key]
  }) }
  regional_counts = { for key, shape in local.shape_contexts : key => {
    region                  = shape.region, gpu_shape = shape.shape,
    memory_gb_per_gpu       = try(shape.memory_bytes_per_gpu / 1e9, null),
    minimum_model_hosts     = local.minimum_model_hosts[key], model_sizing_basis = local.model_budget_basis,
    limit_increase_possible = anytrue([for ad in values(local.ad_details) : length(ad.limit_increase_requests) > 0 if ad.shape_key == key]),
    gpus_per_host           = length(shape.gpu_counts) == 1 ? shape.gpu_counts[0] : null,
    expected_ads            = length(shape.ads), known_ads = length([for ad in values(local.ad_observations) : ad if ad.shape_key == key && ad.known]),
    known_reported_hosts    = sum(concat([0], [for ad in values(local.ad_observations) : ad.available_hosts if ad.shape_key == key && ad.known])),
    availability_domains    = [for ad in shape.ads : { for field, value in local.ad_details[jsonencode([shape.region, shape.shape, ad])] : field => value if field != "shape_key" }]
  } }
  regional_capacity = { for key, row in local.regional_counts : key => merge(row, {
    coverage            = row.expected_ads > 0 && row.expected_ads == row.known_ads ? "complete" : "partial",
    available_hosts     = row.expected_ads > 0 && row.expected_ads == row.known_ads ? row.known_reported_hosts : null,
    available_gpus      = try(row.expected_ads > 0 && row.expected_ads == row.known_ads ? row.known_reported_hosts * row.gpus_per_host : null, null),
    known_reported_gpus = try(row.known_reported_hosts * row.gpus_per_host, null)
  }) }
  memory_bytes = {
    checkpoint_download = try(var.profile.weights.checkpoint_download_bytes, null),
    checkpoint_tensors  = try(var.profile.weights.tensor_data_bytes, null),
    resident_weights    = try(var.profile.memory.weight_bytes, null),
    kv_per_replica      = try(var.profile.memory.kv_bytes, null),
    full_attention_kv   = try(var.profile.memory.partial.full_attention_kv_bytes, null),
    runtime_allowance   = try(var.profile.memory.runtime_allowance_bytes, null),
    total_estimated     = try(var.profile.memory.recommended_aggregate_bytes, null)
  }
  option_recipes = { for id, option in var.options : id => try(option.serving_configuration.recipe, var.serving_configuration.recipe, {}) }
  option_engines = { for id, option in var.options : id => try(option.serving_configuration.engine, option.engine, var.serving_configuration.engine, {}) }
  choices = { for id, option in var.options : id => {
    region         = option.region, availability_domain = option.availability_domain, gpu_shape = option.gpu_shape,
    gpu_type       = try(one([for row in local.inventory_rows : row.gpu_description if row.region == option.region && row.ad == option.availability_domain && row.shape == option.gpu_shape]), null),
    recommendation = try(option.recommendation, null),
    capacity = {
      observed_at                  = try(option.capacity_observed_at, null),
      ad_available_hosts           = try(option.available_instances, null),
      ad_available_gpus            = try(option.available_instances * option.gpus_per_node, null),
      regional_available_gpus      = local.regional_capacity[jsonencode([option.region, option.gpu_shape])].available_gpus,
      regional_known_reported_gpus = local.regional_capacity[jsonencode([option.region, option.gpu_shape])].known_reported_gpus,
      regional_coverage            = local.regional_capacity[jsonencode([option.region, option.gpu_shape])].coverage,
      entitled_hosts               = try(option.entitled_instances, one([for row in try(var.assessment.shape_observations, []) : row.entitled_instances if row.region == option.region && row.availability_domain == option.availability_domain && row.shape == option.gpu_shape]), null)
    }
    allocation = {
      required_hosts             = option.node_count, gpus_per_host = try(option.gpus_per_node, null),
      allocated_gpus             = try(option.node_count * option.gpus_per_node, null),
      required_gpus_per_replica  = try(option.tensor_parallel_size * option.pipeline_parallel_size, null),
      requested_minimum_replicas = try(option.requested_minimum_replicas, null), replicas = try(option.replicas, null),
      replicas_per_host          = try(option.replicas_per_node, null),
      unused_gpus                = try(option.node_count * option.gpus_per_node - option.replicas * option.tensor_parallel_size * option.pipeline_parallel_size, null),
      tensor_parallel_size       = try(option.tensor_parallel_size, null), pipeline_parallel_size = try(option.pipeline_parallel_size, null)
    }
    memory_gb = {
      per_gpu                      = try(one([for row in local.inventory_rows : row.memory_bytes_per_gpu if row.region == option.region && row.ad == option.availability_domain && row.shape == option.gpu_shape]) / 1e9, option.gpu_memory_bytes / 1e9, null),
      estimated_per_gpu            = try(option.estimated_rank_bytes / 1e9, null),
      aggregate_budget_per_replica = try(option.aggregate_payload_bytes / 1e9, null)
    }
    memory_method            = try(option.memory_status, "analytical_layout_estimate_not_runtime_proof"),
    configuration_status     = try(option.configuration_status, "requires_validation"),
    configuration_origin     = try(option.configuration_origin, "analytical_layout"),
    runtime_validation       = try(option.runtime_validation, "not_run"),
    tasks                    = try(option.serving_configuration.recipe.serving_tasks, []),
    components               = sort([for component, requirement in try(option.platform_plan.components, {}) : component if requirement.required]),
    integration_requirements = [for diagnostic in try(option.platform_plan.diagnostics, []) : diagnostic.code if diagnostic.code != "runtime_not_validated"],
    requires_rdma            = try(option.requires_rdma, false),
    warnings                 = try(option.warnings, []), deployment_requirements = try(option.deployment_requirements, []),
    serving = {
      framework            = try(local.option_engines[id].framework, "vllm"), image = try(local.option_engines[id].image, null),
      version              = try(local.option_engines[id].version, null), platform = try(local.option_engines[id].platform, null),
      args                 = try(local.option_recipes[id].args, []), environment = try(local.option_recipes[id].env, {}),
      original_argv        = try(local.option_recipes[id].api.original_argv, local.option_recipes[id].api.rendering.argv, []),
      original_environment = try(local.option_recipes[id].api.rendering.env, {}),
      source_url           = try(local.option_recipes[id].api.rendering.page_url, local.option_recipes[id].source_url, null),
      source_hardware      = try(local.option_recipes[id].api.selection.hardware, local.option_recipes[id].selected_hardware, null),
      selected_hardware    = try(local.option_recipes[id].selected_hardware, null),
      dependencies         = try(local.option_recipes[id].dependencies, []), companions = try(local.option_recipes[id].companions, [])
    },
    links = {
      launch_url   = try(var.publications[id].launch_url, null), download_url = try(var.publications[id].download_url, null),
      published_at = try(var.publications[id].published_at, null), expires_at = try(var.publications[id].expires_at, null),
      model_deployment = {
        launch_url = try(var.model_publications[id].launch_url, null), download_url = try(var.model_publications[id].download_url, null),
        expires_at = try(var.model_publications[id].expires_at, null)
      }
    }
  } }
  summary = {
    schema_version = "4.0", scan = var.scan, publication = var.publication,
    model = {
      repository              = try(var.profile.model.repository, null), revision = try(var.profile.model.resolved_revision, null),
      architecture            = try(var.profile.architecture.kind, null),
      model_type              = try(var.profile.architecture.model_type, null), architecture_classes = try(var.profile.architecture.architectures, []),
      dimensions              = { for key, value in try(var.profile.architecture.attention, {}) : key => value if key != "layer_types" },
      experts                 = try(var.profile.architecture.experts, null), experts_per_token = try(var.profile.architecture.experts_per_token, null),
      declared_context_length = try(var.profile.architecture.declared_context_length, null), quantization = try(var.profile.architecture.quantization, null),
      huggingface_url         = try(var.profile.model.url, null), library = try(var.profile.model.library, null), license = try(var.profile.model.license, null),
      gated                   = try(var.profile.model.gated, null), created_at = try(var.profile.model.created_at, null), last_modified = try(var.profile.model.last_modified, null),
      checkpoint_formats      = try(var.profile.weights.checkpoint_formats, []), selected_checkpoint = try(var.profile.weights.selected_checkpoint, null),
      parameter_count         = try(var.profile.weights.tensor_elements, null), parameters_by_dtype = try(var.profile.weights.elements_by_dtype, {}),
      weights_source          = try(var.profile.weights.source, null),
      declared_pipeline       = try(var.profile.model.pipeline_tag, null),
      context_length          = try(var.profile.memory.assumptions.context_length, null),
      concurrency_per_replica = try(var.profile.memory.assumptions.concurrency, null),
      memory_status           = try(var.profile.memory.status, "unknown"), memory_reasons = try(var.profile.memory.reasons, []),
      memory_gb               = { for name, bytes in local.memory_bytes : name => bytes == null ? null : bytes / 1e9 },
      safety_margin_fraction  = try(var.profile.memory.assumptions.safety_margin_fraction, null)
      memory_assumptions      = try(var.profile.memory.assumptions, {}), recipe_memory_budget_gb = try(var.assessment.recipe_options.memory_budget_bytes / 1e9, null)
      partial_memory          = try(var.profile.memory.partial, {}), planning_memory = try(var.assessment.recipe_options.memory_budget_breakdown, {})
    },
    recommended_option_id = try(var.assessment.recommended_selection_id, null),
    recommendation_basis  = try(var.assessment.recommendation_basis, "not_established"),
    recommendation_policy = try(var.assessment.recommendation_policy, null),
    option_count          = length(local.choices), published_option_count = length(var.publications),
    options               = local.choices,
    regional_capacity     = [for key in sort(keys(local.regional_capacity)) : { for field, value in local.regional_capacity[key] : field => value if field != "gpu_counts" } if local.regional_capacity[key].known_reported_hosts > 0],
    status                = length(local.choices) > 0 ? "confirmed_capacity_options_available" : "no_confirmed_options",
    failure_summary = length(local.choices) > 0 ? [] : distinct(concat(
      try(var.assessment.blocking_reasons, []),
      [for request in try(var.assessment.limit_increase_recommendations, []) : "GPU limit increase: ${request.limit_name} in ${request.region}${request.availability_domain == null ? "" : "/${request.availability_domain}"}; current limit ${request.current_limit}."],
      flatten([for row in try(var.assessment.shape_observations, []) : try(row.exclusion_reasons, [])]),
      length(try(var.assessment.blocking_reasons, [])) == 0 && length(try(var.assessment.shape_observations, [])) == 0 ? ["No confirmed model/hardware options were produced. Review model requirements and regional capacity and limit details."] : []
    )),
    notices = ["Memory uses decimal GB (1 GB = 1,000,000,000 bytes). Null means unknown, not zero.", "Regional counts sum unique whole-AD observations of one exact shape only. Partial coverage has no complete regional total; known_reported counts are a lower bound.", "Different shapes may share supply. Entitlement ceilings are not additive across ADs or regions. Capacity is a snapshot, not a reservation.", "All serving configurations require runtime validation; infrastructure links do not establish CUDA/RDMA/API/performance compatibility."],
  }
}
output "summary" { value = local.summary }
output "html" { value = templatefile("${path.module}/report.html.tftpl", {
  report_json   = jsonencode(local.summary),
  report_script = file("${path.module}/report.js"),
  theme_css     = join("\n", [file("${path.module}/styles/tokens.css"), file("${path.module}/styles/app-shell.css"), file("${path.module}/styles/report.css")])
}) }
