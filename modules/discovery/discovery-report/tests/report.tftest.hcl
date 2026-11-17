# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variables {
  profile = {
    model   = { repository = "org/model", resolved_revision = "pinned", url = "https://huggingface.co/org/model/tree/pinned", license = "apache-2.0" }, architecture = { kind = "dense", model_type = "llama", architectures = ["LlamaForCausalLM"], attention = { layers = 32, heads = 32, kv_heads = 8, head_dim = 128 } },
    weights = { checkpoint_download_bytes = 4100000000, tensor_data_bytes = 4000000000, checkpoint_formats = ["safetensors"], tensor_elements = 2000000000, elements_by_dtype = { BF16 = 2000000000 } },
    memory  = { status = "estimated", reasons = [], weight_bytes = 4000000000, kv_bytes = 2000000000, runtime_allowance_bytes = 1000000000, recommended_aggregate_bytes = 8400000000, assumptions = { context_length = 4096, concurrency = 4, safety_margin_fraction = 0.2 } }
  }
  assessment            = { recommended_selection_id = "selected", shape_observations = [], blocking_reasons = [] }
  scan                  = { observation_id = "fixture", assessed_regions = ["region-one"] }
  serving_configuration = { status = "requires_validation" }
  options = { selected = {
    region               = "region-one", availability_domain = "AD-1", gpu_shape = "GPU.8", gpus_per_node = 8, node_count = 1,
    replicas             = 2, replicas_per_node = 2, requested_minimum_replicas = 1, tensor_parallel_size = 4, pipeline_parallel_size = 1,
    available_instances  = 17, entitled_instances = 2, capacity_observed_at = "2026-11-13T00:00:00Z", estimated_rank_bytes = 30000000000,
    configuration_status = "suggested_requires_validation", runtime_validation = "not_run"
  } }
  publications = { selected = { launch_url = "https://cloud.oracle.com/resourcemanager/stacks/create?region=region-one&zipUrl=fixture", download_url = "https://objectstorage.example/p/fixture.zip", published_at = "2026-11-13T01:00:00Z", expires_at = "2026-11-14T01:00:00Z" } }
  model_publications = { selected = { launch_url = "https://cloud.oracle.com/resourcemanager/stacks/create?region=region-one&zipUrl=model", download_url = "https://objectstorage.example/p/model.zip", expires_at = "2026-11-14T01:00:00Z" } }
  regions = [{
    inventory = { region = "region-one", availability_domains = [for ad in ["AD-1", "AD-2"] : { name = ad, shapes = [{ shape = "GPU.8", gpus = 8, gpu_memory_bytes_per_gpu = 40000000000, quota_names = ["gpu-count"] }] }], limits = [for ad in ["AD-1", "AD-2"] : { name = "gpu-count", scope_type = "AD", availability_domain = ad, description = "GPUs for test instances", tenancy_limit = 64 }] },
    capacity  = { region = "region-one", availability_domains = [for ad, count in { "AD-1" = 17, "AD-2" = 3 } : { name = ad, assessment = { observed_at = "2026-11-13T00:00:00Z", shapes = [{ shape = "GPU.8", available_instances = count, requested_instances = 1, availability_status = "AVAILABLE", fault_domain = null }] } }] }
  }]
}
run "actual_capacity_packing_memory_and_all_links_are_compact" {
  command = plan
  assert {
    condition     = output.summary.options.selected.capacity.ad_available_hosts == 17 && output.summary.options.selected.capacity.ad_available_gpus == 136 && output.summary.options.selected.allocation.required_hosts == 1 && output.summary.options.selected.allocation.allocated_gpus == 8 && output.summary.options.selected.allocation.required_gpus_per_replica == 4 && output.summary.options.selected.allocation.replicas == 2 && output.summary.options.selected.allocation.unused_gpus == 0
    error_message = "Observed physical capacity must not be confused with the synthetic request threshold, required hosts, or per-replica GPU count."
  }
  assert {
    condition     = output.summary.regional_capacity[0].coverage == "complete" && output.summary.regional_capacity[0].available_gpus == 160 && output.summary.options.selected.capacity.entitled_hosts == 2 && output.summary.model.memory_gb.resident_weights == 4 && output.summary.model.memory_gb.kv_per_replica == 2 && output.summary.options.selected.memory_gb.per_gpu == 40
    error_message = "Aggregate physical capacity only across unique ADs of the exact shape; keep entitlement separate and label decimal GB consistently."
  }
  assert {
    condition     = output.summary.option_count == 1 && output.summary.options.selected.links.launch_url == var.publications.selected.launch_url && output.summary.options.selected.links.download_url == var.publications.selected.download_url && output.summary.options.selected.links.model_deployment.launch_url == var.model_publications.selected.launch_url && output.summary.options.selected.links.expires_at == var.publications.selected.expires_at && !contains(keys(output.summary), "diagnostics")
    error_message = "The embedded report data must retain both infrastructure/model launch and PAR URLs with exact expiry."
  }
  assert {
    condition = output.summary.model.dimensions.layers == 32 && output.summary.model.checkpoint_formats == ["safetensors"] && output.summary.model.parameter_count == 2000000000 && output.summary.model.model_type == "llama"
    error_message = "Present existing structured model metadata without additional lookups."
  }
}

run "show_limit_increases_even_when_another_option_is_usable" {
  command = plan
  variables {
    regions = [for region in var.regions : merge(region, { inventory = merge(region.inventory, { limits = [for limit in region.inventory.limits : merge(limit, { tenancy_limit = limit.availability_domain == "AD-1" ? 0 : 64 })] }) })]
  }
  assert {
    condition = output.summary.option_count == 1 && output.summary.regional_capacity[0].limit_increase_possible && length(output.summary.regional_capacity[0].availability_domains[0].limit_increase_requests) == 1 && output.summary.regional_capacity[0].availability_domains[0].limit_increase_requests[0].minimum_gpus_for_whole_hosts == 8
    error_message = "Positive physical capacity with insufficient limits stays visible even when another confirmed deployment option exists; request whole-host GPU units."
  }
}

run "zero_capacity_is_not_a_limit_increase_opportunity" {
  command = plan
  variables {
    regions = [for region in var.regions : merge(region, {
      inventory = merge(region.inventory, { limits = [for limit in region.inventory.limits : merge(limit, { tenancy_limit = 0 })] }),
      capacity = merge(region.capacity, { availability_domains = [for ad in region.capacity.availability_domains : merge(ad, { assessment = merge(ad.assessment, { shapes = [for shape in ad.assessment.shapes : merge(shape, { available_instances = 0, availability_status = "OUT_OF_HOST_CAPACITY" })] }) })] })
    })]
  }
  assert {
    condition = length(output.summary.regional_capacity) == 0
    error_message = "Zero physical capacity stays hidden even with zero limits."
  }
}

run "unknown_model_size_remains_explicit_in_limit_review" {
  command = plan
  variables {
    profile = { model = { repository = "org/custom" }, memory = { status = "unsupported", reasons = ["Unknown architecture"] } }
    regions = [for region in var.regions : merge(region, { inventory = merge(region.inventory, { limits = [for limit in region.inventory.limits : merge(limit, { tenancy_limit = 0 })] }) })]
  }
  assert {
    condition = output.summary.regional_capacity[0].limit_increase_possible && output.summary.regional_capacity[0].minimum_model_hosts == null && output.summary.regional_capacity[0].availability_domains[0].limit_increase_requests[0].model_fit == "unknown_validate_model_sizing_first"
    error_message = "Show potential limit review without claiming unknown model sizing is a deployable fit."
  }
}

run "negative_unknown_limits_are_not_presented_as_insufficient_quotas" {
  command = plan
  variables {
    regions = [for region in var.regions : merge(region, { inventory = merge(region.inventory, { limits = [for limit in region.inventory.limits : merge(limit, { tenancy_limit = -1 })] }) })]
  }
  assert {
    condition = !output.summary.regional_capacity[0].limit_increase_possible
    error_message = "A negative/sentinel quota value must not become a guessed limit-increase requirement."
  }
}
run "partial_ad_coverage_has_no_false_regional_total" {
  command = plan
  variables { regions = [for region in var.regions : merge(region, { capacity = merge(region.capacity, { availability_domains = [region.capacity.availability_domains[0]] }) })] }
  assert {
    condition     = output.summary.regional_capacity[0].coverage == "partial" && output.summary.regional_capacity[0].available_gpus == null && output.summary.regional_capacity[0].known_reported_gpus == 136 && output.summary.regional_capacity[0].known_ads == 1 && output.summary.regional_capacity[0].expected_ads == 2
    error_message = "An unassessed AD leaves the regional total unknown while retaining the count actually reported by known ADs."
  }
}
run "duplicate_identical_ad_reports_are_not_counted_twice" {
  command = plan
  variables { regions = [for region in var.regions : merge(region, { capacity = merge(region.capacity, { availability_domains = concat(region.capacity.availability_domains, [region.capacity.availability_domains[0]]) }) })] }
  assert {
    condition     = output.summary.regional_capacity[0].available_hosts == 20 && output.summary.regional_capacity[0].available_gpus == 160
    error_message = "Repeated identical observations of one AD must not inflate regional GPU totals."
  }
}
run "conflicting_ad_reports_are_ambiguous_not_additive" {
  command = plan
  variables { regions = [for region in var.regions : merge(region, { capacity = merge(region.capacity, { availability_domains = concat(region.capacity.availability_domains, [{ name = "AD-1", assessment = { observed_at = "other", shapes = [{ shape = "GPU.8", available_instances = 10, availability_status = "AVAILABLE", fault_domain = null }] } }]) }) })] }
  assert {
    condition     = output.summary.regional_capacity[0].available_gpus == null && output.summary.regional_capacity[0].known_reported_gpus == 24
    error_message = "Conflicting observations do not establish one whole-AD count; only unambiguous ADs contribute to the known lower bound."
  }
}
run "fault_domain_counts_are_not_whole_ad_capacity" {
  command = plan
  variables { regions = [for region in var.regions : merge(region, { capacity = merge(region.capacity, { availability_domains = [for ad in region.capacity.availability_domains : merge(ad, { assessment = merge(ad.assessment, { shapes = [for shape in ad.assessment.shapes : merge(shape, { fault_domain = "FD-1" })] }) })] }) })] }
  assert {
    condition     = length(output.summary.regional_capacity) == 0
    error_message = "A fault-domain report must never be silently presented as full AD or regional capacity."
  }
}
run "alternative_shapes_keep_independent_regional_counts" {
  command = plan
  variables {
    regions = [for region in var.regions : merge(region, {
      inventory = merge(region.inventory, { availability_domains = [for ad in region.inventory.availability_domains : merge(ad, { shapes = concat(ad.shapes, [{ shape = "GPU.4", gpus = 4, gpu_memory_bytes_per_gpu = 24000000000 }]) })] }),
      capacity  = merge(region.capacity, { availability_domains = [for ad in region.capacity.availability_domains : merge(ad, { assessment = merge(ad.assessment, { shapes = concat(ad.assessment.shapes, [{ shape = "GPU.4", available_instances = 5, availability_status = "AVAILABLE", fault_domain = null }]) }) })] })
    })]
  }
  assert {
    condition     = length(output.summary.regional_capacity) == 2 && sum([for row in output.summary.regional_capacity : row.available_gpus if row.gpu_shape == "GPU.4"]) == 40 && sum([for row in output.summary.regional_capacity : row.available_gpus if row.gpu_shape == "GPU.8"]) == 160 && !contains(keys(output.summary), "total_available_gpus")
    error_message = "Exact shape groups may share supply and cannot be merged into an apparent total regional GPU inventory."
  }
}
run "unsupported_memory_remains_unknown_and_failure_is_actionable" {
  command = plan
  variables {
    options      = {}
    publications = {}
    profile      = { model = { repository = "org/custom" }, memory = { status = "unsupported", reasons = ["Hybrid memory estimator unavailable"] } }
    assessment   = { blocking_reasons = ["No supported serving layout"], shape_observations = [] }
  }
  assert {
    condition     = output.summary.model.memory_gb.resident_weights == null && output.summary.model.memory_gb.kv_per_replica == null && output.summary.option_count == 0 && contains(output.summary.failure_summary, "No supported serving layout") && output.summary.status == "no_confirmed_options"
    error_message = "Unknown memory is null, not zero; an empty option list must retain an explanation."
  }
}
run "html_payload_cannot_close_the_data_script" {
  command = plan
  variables { profile = merge(var.profile, { model = { repository = "</script><script>pwn()</script>", resolved_revision = "fixture" } }) }
  assert {
    condition     = !strcontains(output.html, "</script><script>pwn()") && strcontains(output.html, "\\u003c/script\\u003e") && !strcontains(output.html, ".innerHTML")
    error_message = "Use Terraform jsonencode escaping and DOM textContent; model metadata must not become executable markup."
  }
}

run "configured_limits_preserve_scope_and_selected_AD_without_adding_shared_limits" {
  command = plan
  variables {
    regions = [for region in var.regions : merge(region, {inventory=merge(region.inventory, {
      availability_domains=[for ad in region.inventory.availability_domains : merge(ad, {shapes=[for shape in ad.shapes : merge(shape, {quota_names=["gpu-count","regional-gpu","global-gpu"]})]})],
      limits=concat([for limit in region.inventory.limits : merge(limit, {
        tenancy_limit=limit.availability_domain=="AD-1" ? 64 : 99,
        resource_availability={status="observed",available=24,fractional_availability=null}
      })], [
        {name="regional-gpu",scope_type="REGION",availability_domain=null,description="GPUs for test instances",tenancy_limit=32,resource_availability={status="observed",available=24,fractional_availability=16.5,effective_quota_value=20}},
        {name="global-gpu",scope_type="GLOBAL",availability_domain=null,description="GPUs for test instances",tenancy_limit=128,resource_availability={status="observed",available=96}}
      ])
    })})]
  }
  assert {
    condition = length(output.summary.options.selected.capacity.limits)==3 && !contains([for limit in output.summary.options.selected.capacity.limits : limit.current_limit],99) && output.summary.options.selected.capacity.ad_available_gpus==136 && !contains(keys(output.summary.options.selected.capacity),"regional_available_gpus")
    error_message = "Use the selected AD's supply and limits; never the regional supply or another AD's limit."
  }
  assert {
    condition = length([for limit in output.summary.regional_capacity[0].limits : limit if limit.scope=="REGION"])==1 && one([for limit in output.summary.options.selected.capacity.limits : limit if limit.scope=="REGION"]).current_limit==32 && one([for limit in output.summary.options.selected.capacity.limits : limit if limit.scope=="REGION"]).remaining_headroom==16.5 && one([for limit in output.summary.options.selected.capacity.limits : limit if limit.scope=="REGION"]).effective_quota==20
    error_message = "Shared regional limits appear once, not summed per AD; configured ceiling, fractional remaining headroom and effective quota remain separate."
  }
}
run "missing_observations_and_unknown_units_do_not_become_GPU_limits" {
  command = plan
  variables {
    regions = [for region in var.regions : merge(region, {inventory=merge(region.inventory, {limits=[for limit in region.inventory.limits : merge(limit, {tenancy_limit=-1,description="Unspecified service units",resource_availability={status="unknown",available=24}})]})})]
  }
  assert {
    condition = output.summary.options.selected.capacity.limits[0].current_limit==null && output.summary.options.selected.capacity.limits[0].remaining_headroom==null && output.summary.options.selected.capacity.limits[0].unit=="units (unverified)"
    error_message = "Sentinel or missing limits/headroom stay unknown, and unverified quota units must not be called GPUs."
  }
}
run "zero_limit_and_fractional_zero_headroom_remain_visible" {
  command = plan
  variables {
    regions = [for region in var.regions : merge(region, {inventory=merge(region.inventory, {limits=[for limit in region.inventory.limits : merge(limit, {tenancy_limit=0,resource_availability={status="observed",available=24,fractional_availability=0,effective_quota_value=0}})]})})]
  }
  assert {
    condition = output.summary.options.selected.capacity.limits[0].current_limit==0 && output.summary.options.selected.capacity.limits[0].remaining_headroom==0 && output.summary.options.selected.capacity.limits[0].effective_quota==0 && output.summary.regional_capacity[0].limit_increase_possible
    error_message = "Zero is observed evidence; fractional zero must take precedence over the integer available field and remain visible for limit-increase alternatives."
  }
}

run "regional_capacity_preserves_incompatible_dtype_evidence" {
  command = plan
  variables {
    options = {}
    publications = {}
    assessment = {precision_compatibility={"GPU.8"={status="not_compatible",required_precision="fp8",reason="Native FP8 kernels unavailable"}}}
  }
  assert {
    condition = output.summary.option_count == 0 && output.summary.regional_capacity[0].available_hosts == 20 && output.summary.regional_capacity[0].dtype_compatibility.status == "not_compatible"
    error_message = "Incompatible dtype cannot erase physical capacity or fabricate a deployment option."
  }
}

run "gpu_lower_bound_keeps_whole_host_allocation_separate" {
  command = plan
  variables { profile = merge(var.profile, { memory = merge(var.profile.memory, { recommended_aggregate_bytes = 60000000000 }) }) }
  assert {
    condition     = output.summary.regional_capacity[0].minimum_model_gpus == 2 && output.summary.regional_capacity[0].minimum_model_hosts == 1 && output.summary.regional_capacity[0].gpus_per_host == 8
    error_message = "The existing 60GB budget needs at least two 40GB GPUs after runtime allowance, while the eight-GPU shape still allocates one whole host."
  }
}
