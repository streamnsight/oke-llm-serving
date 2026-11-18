# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variables {
  profile = { architecture = { kind = "dense", attention = { layer_types = ["full_attention", "full_attention"] } } }
  serving = { engine = { framework = "vllm" }, recipe = { args = [] } }
}
run "uniform_cache_is_eligible_but_not_runtime_validated" {
  command = plan
  assert {
    condition     = output.assessment.cache_layout == "uniform_attention" && output.assessment.lmcache.inprocess.selectable && output.assessment.lmcache.mp.selectable && output.assessment.lmcache.mp.status == "requires_image_validation"
    error_message = "Known uniform caches can select either adapter without claiming exact-image validation."
  }
  assert {
    condition     = !output.assessment.routing.kvaware.selectable && !contains(output.assessment.routing_modes, "kvaware") && strcontains(join(" ", output.assessment.routing.kvaware.reasons), "chat messages")
    error_message = "The pinned router's chat limitation applies even to a conventional model."
  }
}
run "hybrid_cache_requires_an_assessed_MP_path" {
  command = plan
  variables { profile = { architecture = { kind = "hybrid_moe", attention = { layer_types = ["full_attention", "linear_attention"] } } } }
  assert {
    condition     = output.assessment.requires_hma && !output.assessment.lmcache.inprocess.selectable && !contains(output.assessment.lmcache_modes, "inprocess") && output.assessment.lmcache.mp.selectable && length(output.assessment.routing.kvaware.reasons) == 3
    error_message = "Hybrid metadata must hide the current in-process path and retain MP's required image validation."
  }
}
run "layer_metadata_overrides_a_misleading_dense_label" {
  command = plan
  variables { profile = { architecture = { kind = "dense", attention = { layer_types = ["linear_attention"] } } } }
  assert {
    condition     = output.assessment.requires_hma && !output.assessment.lmcache.inprocess.selectable
    error_message = "A generic dense label must not mask hybrid layers."
  }
}
run "unknown_layout_is_not_treated_as_uniform" {
  command = plan
  variables { profile = {} }
  assert {
    condition     = output.assessment.cache_layout == "unverified" && !output.assessment.lmcache.inprocess.selectable
    error_message = "Missing model metadata must not grant legacy cache compatibility."
  }
}
run "multi_host_cache_layout_is_not_assessed" {
  command = plan
  variables {
    hosts_per_replica      = 2
    pipeline_parallel_size = 2
  }
  assert {
    condition     = !output.assessment.lmcache.mp.selectable && !output.assessment.lmcache.inprocess.selectable && output.assessment.lmcache_modes == ["recipe", "disabled"]
    error_message = "vLLM multiprocessing PP is not proof of LMCache MP compatibility."
  }
}
run "prefix_cache_conflict_is_explicit" {
  command = plan
  variables { serving = { engine = { framework = "vllm" }, recipe = { args = ["--no-enable-prefix-caching"] } } }
  assert {
    condition     = !output.assessment.lmcache.mp.selectable && strcontains(join(" ", output.assessment.lmcache.mp.reasons), "recipe disables prefix caching")
    error_message = "Do not offer an adapter that contradicts the frozen recipe."
  }
}
run "other_engine_is_not_a_vllm_adapter" {
  command = plan
  variables { serving = { engine = { framework = "sglang" } } }
  assert {
    condition     = !output.assessment.lmcache.mp.selectable && !output.assessment.lmcache.inprocess.selectable
    error_message = "Upstream support in another engine is not an implemented adapter in our stack."
  }
}
