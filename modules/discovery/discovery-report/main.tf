# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform { required_version = ">= 1.5.0" }
locals {
  inventory_rows = flatten([for region in var.regions : [for ad in try(region.inventory.availability_domains, []) : [for shape in ad.shapes : {
    region          = region.inventory.region, ad = ad.name, shape = shape.shape, gpus = shape.gpus,
    gpu_description = try(shape.gpu_description, null), memory_bytes_per_gpu = try(shape.gpu_memory_bytes_per_gpu, null)
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
    region = jsondecode(key)[0], shape = jsondecode(key)[1]
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
  regional_counts = { for key, shape in local.shape_contexts : key => {
    region               = shape.region, gpu_shape = shape.shape,
    gpus_per_host        = length(shape.gpu_counts) == 1 ? shape.gpu_counts[0] : null,
    expected_ads         = length(shape.ads), known_ads = length([for ad in values(local.ad_observations) : ad if ad.shape_key == key && ad.known]),
    known_reported_hosts = sum(concat([0], [for ad in values(local.ad_observations) : ad.available_hosts if ad.shape_key == key && ad.known])),
    availability_domains = [for ad in shape.ads : { for field, value in local.ad_observations[jsonencode([shape.region, shape.shape, ad])] : field => value if field != "shape_key" }]
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
    runtime_allowance   = try(var.profile.memory.runtime_allowance_bytes, null),
    total_estimated     = try(var.profile.memory.recommended_aggregate_bytes, null)
  }
  choices = { for id, option in var.options : id => {
    region   = option.region, availability_domain = option.availability_domain, gpu_shape = option.gpu_shape,
    gpu_type = try(one([for row in local.inventory_rows : row.gpu_description if row.region == option.region && row.ad == option.availability_domain && row.shape == option.gpu_shape]), null),
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
    links = {
      launch_url   = try(var.publications[id].launch_url, null), download_url = try(var.publications[id].download_url, null),
      published_at = try(var.publications[id].published_at, null), expires_at = try(var.publications[id].expires_at, null)
    },
    skip_gpu_allocation = try(var.publications[id].skip_gpu_allocation, false)
  } }
  summary = {
    schema_version = "3.0", scan = var.scan,
    model = {
      repository              = try(var.profile.model.repository, null), revision = try(var.profile.model.resolved_revision, null),
      architecture            = try(var.profile.architecture.kind, null),
      declared_pipeline       = try(var.profile.model.pipeline_tag, null),
      context_length          = try(var.profile.memory.assumptions.context_length, null),
      concurrency_per_replica = try(var.profile.memory.assumptions.concurrency, null),
      memory_status           = try(var.profile.memory.status, "unknown"), memory_reasons = try(var.profile.memory.reasons, []),
      memory_gb               = { for name, bytes in local.memory_bytes : name => bytes == null ? null : bytes / 1e9 },
      safety_margin_fraction  = try(var.profile.memory.assumptions.safety_margin_fraction, null)
    },
    recommended_option_id = try(var.assessment.recommended_selection_id, null),
    recommendation_basis  = try(var.assessment.recommendation_basis, "not_established"),
    option_count          = length(local.choices), published_option_count = length(var.publications),
    options               = local.choices,
    regional_capacity     = [for key in sort(keys(local.regional_capacity)) : { for field, value in local.regional_capacity[key] : field => value if field != "gpu_counts" }],
    status                = length(local.choices) > 0 ? "confirmed_capacity_options_available" : "no_confirmed_options",
    failure_summary = length(local.choices) > 0 ? [] : distinct(concat(
      try(var.assessment.blocking_reasons, []),
      [for request in try(var.assessment.limit_increase_recommendations, []) : "GPU limit increase: ${request.limit_name} in ${request.region}${request.availability_domain == null ? "" : "/${request.availability_domain}"}; current limit ${request.current_limit}."],
      flatten([for row in try(var.assessment.shape_observations, []) : try(row.exclusion_reasons, [])]),
      length(try(var.assessment.blocking_reasons, [])) == 0 && length(try(var.assessment.shape_observations, [])) == 0 ? ["No confirmed model/hardware options were produced; enable diagnostic details to inspect the assessment."] : []
    )),
    notices     = ["Memory uses decimal GB (1 GB = 1,000,000,000 bytes). Null means unknown, not zero.", "Regional counts sum unique whole-AD observations of one exact shape only. Partial coverage has no complete regional total; known_reported counts are a lower bound.", "Different shapes may share supply. Entitlement ceilings are not additive across ADs or regions. Capacity is a snapshot, not a reservation.", "All serving configurations require runtime validation; infrastructure links do not establish CUDA/RDMA/API/performance compatibility."],
    diagnostics = var.include_diagnostics ? { profile = var.profile, assessment = var.assessment, regions = var.regions, serving_configuration = var.serving_configuration } : null
  }
}
output "summary" { value = local.summary }
output "html" { value = templatefile("${path.module}/report.html.tftpl", { report_json = jsonencode(local.summary) }) }
