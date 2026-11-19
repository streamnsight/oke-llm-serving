# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variables {
  profile = { architecture = {
    kind      = "dense", text_only = true, causal_generation = true,
    attention = { layout = "uniform_attention", layer_types = ["full_attention", "full_attention"] }
  } }
  serving_configuration = { engine = { framework = "vllm" }, recipe = { args = [] } }
  options = { selected = {
    region                     = "region-one", availability_domain = "AD-1", gpu_shape = "BM.GPU.A10.4",
    gpus_per_node              = 4, node_count = 1, tensor_parallel_size = 2, pipeline_parallel_size = 1, hosts_per_replica = 1,
    requested_minimum_replicas = 1, replicas = 2, replicas_per_node = 2,
    available_instances        = 4, entitled_instances = 4, availability = "available_at_scan"
  } }
}

run "TP2_prefill_and_decode_share_one_four_GPU_host" {
  command = plan
  assert {
    condition     = output.layouts.disaggregated.status == "eligible_for_testing" && output.layouts.disaggregated.options.selected.prefill_replicas == 1 && output.layouts.disaggregated.options.selected.decode_replicas == 1 && output.layouts.disaggregated.options.selected.allocation.required_hosts == 1 && output.layouts.disaggregated.options.selected.allocation.allocated_gpus == 4 && output.layouts.disaggregated.options.selected.allocation.unused_gpus == 0
    error_message = "P/D requires two full model instances; TP2 per role fits one 4-GPU host."
  }
  assert {
    condition     = output.layouts.aggregated.options.selected.allocation.replicas == 2 && output.layouts.aggregated.options.selected.allocation.required_hosts == 1 && output.layouts.aggregated.options.selected.allocation.required_gpus_per_replica == 2 && length(output.layouts.aggregated.options.selected.model_variables) == 0
    error_message = "Aggregated recommendations and existing defaults must remain unchanged."
  }
}
run "TP4_requires_two_whole_hosts_and_eight_GPUs" {
  command = plan
  variables { options = { selected = merge(var.options.selected, { tensor_parallel_size = 4, replicas = 1, replicas_per_node = 1 }) } }
  assert {
    condition     = output.layouts.disaggregated.options.selected.allocation.required_hosts == 2 && output.layouts.disaggregated.options.selected.allocation.allocated_gpus == 8 && output.layouts.disaggregated.options.selected.infrastructure_variables.node_count == 2 && output.layouts.disaggregated.options.selected.model_variables.replicas == 1
    error_message = "One TP4 role fills a host; prefill and decode cannot share its GPUs."
  }
}
run "spare_complete_slots_become_decode_instances" {
  command = plan
  variables { options = { selected = merge(var.options.selected, { tensor_parallel_size = 1, replicas = 4, replicas_per_node = 4 }) } }
  assert {
    condition     = output.layouts.disaggregated.options.selected.decode_replicas == 3 && output.layouts.disaggregated.options.selected.allocation.requested_minimum_replicas == 1 && output.layouts.disaggregated.options.selected.allocation.required_hosts == 1 && output.layouts.disaggregated.options.selected.allocation.replicas_per_host == 4 && output.layouts.disaggregated.options.selected.model_variables.autoscaling_enabled == false && output.layouts.disaggregated.options.selected.model_variables.router_enabled == true && output.layouts.disaggregated.options.selected.model_variables.prefill_replicas == 1
    error_message = "Fill unused whole role slots while retaining native numeric/boolean quick-create values."
  }
}
run "minimum_decode_quantity_is_preserved_before_packing" {
  command = plan
  variables { options = { selected = merge(var.options.selected, { requested_minimum_replicas = 4, node_count = 2, replicas = 4 }) } }
  assert {
    condition     = output.layouts.disaggregated.options.selected.allocation.required_hosts == 3 && output.layouts.disaggregated.options.selected.decode_replicas == 5 && output.layouts.disaggregated.options.selected.model_variables.min_replicas == 5 && output.layouts.disaggregated.options.selected.model_variables.max_replicas == 5
    error_message = "Four requested decode replicas plus prefill need three TP2 hosts, with one spare decode slot."
  }
}
run "physical_capacity_must_cover_both_role_pools_in_the_same_AD" {
  command = plan
  variables { options = {
    selected = merge(var.options.selected, { tensor_parallel_size = 4, available_instances = 1 }),
    other_ad = merge(var.options.selected, { tensor_parallel_size = 4, availability_domain = "AD-2", available_instances = 20 })
  } }
  assert {
    condition     = !contains(keys(output.layouts.disaggregated.options), "selected") && contains(keys(output.layouts.disaggregated.options), "other_ad") && strcontains(join(" ", output.layouts.disaggregated.unavailable_options.selected.reasons), "2 whole hosts (8 allocated GPUs)")
    error_message = "Another AD's physical supply cannot satisfy this AD's P/D deployment."
  }
}
run "positive_but_insufficient_headroom_is_not_a_P_D_option" {
  command = plan
  variables { options = { selected = merge(var.options.selected, { tensor_parallel_size = 4, entitled_instances = 1 }) } }
  assert {
    condition     = output.layouts.disaggregated.status == "capacity_not_confirmed_for_quantity" && length(output.layouts.disaggregated.options) == 0 && strcontains(join(" ", output.layouts.disaggregated.reasons), "quantity-specific entitlement")
    error_message = "Headroom for the ordinary one-host option does not prove headroom for two P/D hosts."
  }
}
run "unknown_capacity_cannot_be_inferred_from_quota" {
  command = plan
  variables { options = { selected = merge(var.options.selected, { available_instances = null }) } }
  assert {
    condition     = length(output.layouts.disaggregated.options) == 0 && length(output.layouts.aggregated.options) == 1
    error_message = "P/D must fail closed on unknown physical capacity without altering the existing base report."
  }
}
run "unknown_headroom_cannot_be_inferred_from_capacity" {
  command = plan
  variables { options = { selected = merge(var.options.selected, { entitled_instances = null }) } }
  assert {
    condition     = length(output.layouts.disaggregated.options) == 0 && strcontains(join(" ", output.layouts.disaggregated.reasons), "headroom")
    error_message = "Unknown entitlement cannot be replaced by positive physical capacity."
  }
}
run "exact_AD_quantity_observation_can_supply_missing_option_entitlement" {
  command = plan
  variables {
    options = { selected = merge(var.options.selected, { tensor_parallel_size = 4, entitled_instances = null }) }
    assessment = { shape_observations = [{
      region             = "region-one", availability_domain = "AD-1", shape = "BM.GPU.A10.4",
      entitled_instances = 2, limit_status = "positive", headroom_status = "positive", quota_mapping_complete = true,
      capacity_status    = "positive", capacity = { availability_status = "AVAILABLE", available_instances = 4, fault_domain = null }
    }] }
  }
  assert {
    condition     = output.layouts.disaggregated.options.selected.allocation.required_hosts == 2
    error_message = "Reuse exact-scoped quantity evidence rather than requiring a duplicate scan."
  }
}
run "another_AD_cannot_supply_missing_entitlement" {
  command = plan
  variables {
    options    = { selected = merge(var.options.selected, { entitled_instances = null }) }
    assessment = { shape_observations = [{ region = "region-one", availability_domain = "AD-2", shape = "BM.GPU.A10.4", entitled_instances = 100, limit_status = "positive", headroom_status = "positive", quota_mapping_complete = true }] }
  }
  assert {
    condition     = length(output.layouts.disaggregated.options) == 0
    error_message = "Entitlement lookup must match the exact region, AD and shape."
  }
}
run "unverified_quota_units_cannot_supply_missing_entitlement" {
  command = plan
  variables {
    options = { selected = merge(var.options.selected, { entitled_instances = null }) }
    assessment = { shape_observations = [{
      region          = "region-one", availability_domain = "AD-1", shape = "BM.GPU.A10.4", entitled_instances = 100, limit_status = "positive", headroom_status = "positive", quota_mapping_complete = false,
      capacity_status = "positive", capacity = { availability_status = "AVAILABLE", available_instances = 4, fault_domain = null }
    }] }
  }
  assert {
    condition     = length(output.layouts.disaggregated.options) == 0 && length(output.layouts.disaggregated.unavailable_options.selected.reasons) == 1 && strcontains(output.layouts.disaggregated.unavailable_options.selected.reasons[0], "entitlement")
    error_message = "A numeric quantity with incomplete quota mapping is not verified GPU headroom."
  }
}
run "conflicting_quantity_observations_are_unknown" {
  command = plan
  variables {
    options = { selected = merge(var.options.selected, { entitled_instances = null }) }
    assessment = { shape_observations = [for count in [1, 4] : {
      region          = "region-one", availability_domain = "AD-1", shape = "BM.GPU.A10.4", entitled_instances = count, limit_status = "positive", headroom_status = "positive", quota_mapping_complete = true,
      capacity_status = "positive", capacity = { availability_status = "AVAILABLE", available_instances = 4, fault_domain = null }
    }] }
  }
  assert {
    condition     = length(output.layouts.disaggregated.options) == 0 && length(output.layouts.disaggregated.unavailable_options.selected.reasons) == 1 && strcontains(output.layouts.disaggregated.unavailable_options.selected.reasons[0], "entitlement")
    error_message = "Conflicting observations must not be summed or reduced to an optimistic quota."
  }
}
run "fault_domain_capacity_is_not_a_whole_AD_observation" {
  command = plan
  variables { options = { selected = merge(var.options.selected, { fault_domain = "FAULT-DOMAIN-1" }) } }
  assert {
    condition     = length(output.layouts.disaggregated.options) == 0 && strcontains(join(" ", output.layouts.disaggregated.reasons), "whole-host scope")
    error_message = "A fault-domain count must not be presented as capacity throughout the selected AD."
  }
}
run "unconfirmed_capacity_scope_stays_unavailable" {
  command = plan
  variables { options = { selected = merge(var.options.selected, { availability = "unknown" }) } }
  assert {
    condition     = length(output.layouts.disaggregated.options) == 0
    error_message = "A positive number without a capacity-confirmed base selection is insufficient."
  }
}
run "matching_observation_without_capacity_scope_is_unknown" {
  command = plan
  variables {
    assessment = { shape_observations = [{
      region          = "region-one", availability_domain = "AD-1", shape = "BM.GPU.A10.4",
      capacity_status = "positive", capacity = { availability_status = "AVAILABLE", available_instances = 4 }
    }] }
  }
  assert {
    condition     = length(output.layouts.disaggregated.options) == 0
    error_message = "A matching observation with omitted capacity scope cannot override whole-AD uncertainty."
  }
}
run "fractional_capacity_is_not_a_whole_host_quantity" {
  command = plan
  variables { options = { selected = merge(var.options.selected, { available_instances = 1.5 }) } }
  assert {
    condition     = length(output.layouts.disaggregated.options) == 0
    error_message = "Never offer a whole-host deployment based on a fractional instance count."
  }
}
run "multi_host_PP_is_outside_the_first_adapter" {
  command = plan
  variables { options = { selected = merge(var.options.selected, { pipeline_parallel_size = 2, hosts_per_replica = 2, node_count = 2 }) } }
  assert {
    condition     = length(output.layouts.disaggregated.options) == 0 && output.layouts.disaggregated.status == "unsupported_by_adapter" && strcontains(join(" ", output.layouts.disaggregated.reasons), "PP=1")
    error_message = "Ordinary multi-host PP must not be reinterpreted as a supported single-host role."
  }
}
run "MoE_with_uniform_attention_is_not_excluded_for_being_MoE" {
  command = plan
  variables { profile = { architecture = { kind = "moe", text_only = true, causal_generation = true, attention = { layout = "uniform_attention", layer_types = ["full_attention"] } } } }
  assert {
    condition     = output.layouts.disaggregated.status == "eligible_for_testing" && length(output.layouts.disaggregated.options) == 1
    error_message = "MoE is not itself a P/D incompatibility; cache layout and recipe integration govern eligibility."
  }
}
run "hybrid_models_have_architecture_reasons_without_model_name_rules" {
  command = plan
  variables { profile = { architecture = { kind = "hybrid_moe", text_only = true, causal_generation = true, attention = { layout = "hybrid", layer_types = ["linear_attention", "full_attention"] } } } }
  assert {
    condition     = length(output.layouts.disaggregated.options) == 0 && strcontains(join(" ", output.layouts.disaggregated.reasons), "uniform attention")
    error_message = "The first adapter must not turn hybrid caches into ordinary attention state."
  }
}
run "multimodal_models_are_not_claimed_text_only" {
  command = plan
  variables { profile = { architecture = { kind = "dense", text_only = false, causal_generation = false, attention = { layout = "unverified", layer_types = ["sliding_attention", "full_attention"] } } } }
  assert {
    condition     = length(output.layouts.disaggregated.options) == 0 && strcontains(join(" ", output.layouts.disaggregated.reasons), "Text-only causal generation")
    error_message = "Mixed attention/multimodal models need an assessed adapter even for text requests."
  }
}
run "recipe_transfer_connectors_are_not_overwritten" {
  command = plan
  variables { serving_configuration = { engine = { framework = "vllm" }, recipe = { args = ["--kv-transfer-config", "existing"] } } }
  assert {
    condition     = length(output.layouts.disaggregated.options) == 0 && strcontains(join(" ", output.layouts.disaggregated.reasons), "transfer, speculative or expert-parallel")
    error_message = "Native P/D cannot silently replace a recipe-owned connector."
  }
}
run "option_recipe_overrides_are_assessed_instead_of_the_fallback" {
  command = plan
  variables {
    options = { selected = merge(var.options.selected, {
      serving_configuration = { engine = { framework = "vllm" }, recipe = { args = ["--enable-expert-parallel"] } }
    }) }
  }
  assert {
    condition     = length(output.layouts.disaggregated.options) == 0 && strcontains(join(" ", output.layouts.disaggregated.reasons), "transfer, speculative or expert-parallel")
    error_message = "The chosen hardware recipe's settings take precedence over generic model defaults."
  }
}
run "eligible_models_without_hardware_have_an_explanation" {
  command = plan
  variables { options = {} }
  assert {
    condition     = output.layouts.disaggregated.status == "no_confirmed_options" && length(output.layouts.disaggregated.options) == 0 && strcontains(join(" ", output.layouts.disaggregated.reasons), "No capacity-confirmed hardware")
    error_message = "An empty hardware list must retain the model-wide eligibility assessment."
  }
}
run "unknown_models_remain_unknown_without_hardware" {
  command = plan
  variables {
    profile = {}
    options = {}
  }
  assert {
    condition     = output.layouts.disaggregated.status == "unknown" && length(output.layouts.disaggregated.reasons) > 0
    error_message = "Unknown model metadata must not disappear behind an empty option list."
  }
}
