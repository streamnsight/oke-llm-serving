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
run "native_PD_is_metadata_eligible_not_runtime_validated" {
  command = plan
  variables { profile = { architecture = { kind = "dense", text_only = true, causal_generation = true, attention = { layout = "uniform_attention", layer_types = ["full_attention"] } } } }
  assert {
    condition     = output.assessment.disaggregation.selectable && output.assessment.disaggregation.status == "eligible_for_testing" && output.assessment.serving_modes == ["aggregated", "disaggregated"]
    error_message = "Text-only uniform attention can test native P/D without claiming exact-image or network validation."
  }
}
run "native_PD_hides_hybrid_and_composite_layouts" {
  command = plan
  variables { profile = { architecture = { kind = "hybrid_dense", text_only = false, attention = { layer_types = ["full_attention", "linear_attention"] } } } }
  assert {
    condition     = !output.assessment.disaggregation.selectable && output.assessment.serving_modes == ["aggregated"] && strcontains(join(" ", output.assessment.disaggregation.reasons), "uniform attention")
    error_message = "The first adapter must not silently reinterpret hybrid/composite state as conventional KV."
  }
}
run "native_PD_does_not_overwrite_recipe_connectors" {
  command = plan
  variables {
    profile = { architecture = { kind = "dense", text_only = true, causal_generation = true, attention = { layout = "uniform_attention", layer_types = ["full_attention"] } } }
    serving = { engine = { framework = "vllm" }, recipe = { args = ["--kv-transfer-config.kv_connector", "LMCacheMPConnector"] } }
  }
  assert {
    condition     = !output.assessment.disaggregation.selectable && strcontains(join(" ", output.assessment.disaggregation.reasons), "transfer, speculative or expert-parallel")
    error_message = "Dotted raw transfer flags are also a connector conflict."
  }
}
run "native_PD_rejects_unassessed_quantized_KV" {
  command = plan
  variables {
    profile = { architecture = { kind = "dense", text_only = true, causal_generation = true, attention = { layout = "uniform_attention", layer_types = ["full_attention"] } } }
    serving = { engine = { framework = "vllm" }, recipe = { args = ["--kv-cache-dtype=fp8"] } }
  }
  assert {
    condition     = !output.assessment.disaggregation.selectable && strcontains(join(" ", output.assessment.disaggregation.reasons), "scale compatibility")
    error_message = "A generic FP8 dtype flag does not prove transferred scales are compatible."
  }
}
run "native_PD_rejects_unimplemented_PP" {
  command = plan
  variables {
    profile                = { architecture = { kind = "dense", text_only = true, causal_generation = true, attention = { layout = "uniform_attention", layer_types = ["full_attention"] } } }
    hosts_per_replica      = 2
    pipeline_parallel_size = 2
  }
  assert {
    condition     = !output.assessment.disaggregation.selectable && strcontains(join(" ", output.assessment.disaggregation.reasons), "PP=1")
    error_message = "Native MP PP support in aggregated serving is not support for P/D PP."
  }
}
run "native_PD_requires_a_causal_generation_task" {
  command = plan
  variables { profile = { architecture = { kind = "dense", text_only = true, causal_generation = false, attention = { layer_types = ["full_attention"] } } } }
  assert {
    condition     = !output.assessment.disaggregation.selectable && strcontains(join(" ", output.assessment.disaggregation.reasons), "classifiers and unknown tasks")
    error_message = "A text-only sequence classifier is not an autoregressive P/D model."
  }
}
