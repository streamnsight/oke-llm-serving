# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform { required_version = ">= 1.5.0" }

variable "profile" { type = any }
variable "serving" { type = any }
variable "hosts_per_replica" {
  type    = number
  default = 1
}
variable "pipeline_parallel_size" {
  type    = number
  default = 1
}

locals {
  requires_hma    = try(startswith(var.profile.architecture.kind, "hybrid_"), false) || try(contains(var.profile.architecture.attention.layer_types, "linear_attention"), false)
  uniform         = !local.requires_hma && try(contains(["dense", "moe"], var.profile.architecture.kind), false) && try(alltrue([for kind in coalesce(try(var.profile.architecture.attention.layer_types, null), []) : contains(["full_attention", "attention"], kind)]), false)
  layout          = local.requires_hma ? "hybrid" : local.uniform ? "uniform_attention" : "unverified"
  single_host     = var.hosts_per_replica == 1 && var.pipeline_parallel_size == 1
  vllm            = try(var.serving.engine.framework, "vllm") == "vllm"
  prefix_disabled = anytrue([for arg in try(var.serving.recipe.args, []) : can(regex("^--no-enable-prefix-caching(=|$)", arg))])
  cache_reasons = compact([
    local.single_host ? "" : "The current LMCache adapter supports single-host TP only; multi-host PP is not assessed.",
    local.vllm ? "" : "The current LMCache adapter requires vLLM.",
    local.prefix_disabled ? "The recipe disables prefix caching, which this LMCache adapter requires." : ""
  ])
  inprocess_reasons = concat(local.cache_reasons, local.uniform ? [] : ["The current in-process adapter requires a known uniform attention cache; this model's cache layout is ${local.layout}."])
  # These are limitations of the pinned integration, not model-name exclusions.
  # Do not enable KV-aware routing solely from model/image recipe selection.
  kvaware_reasons = concat([
    "Production Stack 0.1.14 KV-aware routing does not correctly tokenize chat messages; a complete KV-aware routing integration is unavailable.",
    "Its legacy controller cannot consume LMCache MP cache events."
  ], local.requires_hma ? ["This model uses a hybrid cache that the current in-process connector cannot support."] : local.uniform ? [] : ["The model cache layout is unverified."], local.cache_reasons)
  pd_args     = try(var.serving.recipe.args, [])
  pd_kv_dtype = try(local.pd_args[index(local.pd_args, "--kv-cache-dtype") + 1], trimprefix(one([for arg in local.pd_args : arg if startswith(arg, "--kv-cache-dtype=")]), "--kv-cache-dtype="), "auto")
  pd_reasons = compact([
    try(var.serving.engine.framework, "unknown") == "vllm" ? "" : "Native P/D requires a declared vLLM serving engine.",
    local.uniform ? "" : "The first native NIXL P/D adapter requires uniform attention; hybrid and unverified cache layouts need a separate assessment.",
    try(var.profile.architecture.attention.layout, "unverified") == "uniform_attention" ? "" : "The normalized model profile has no verified uniform-attention layout; refresh discovery or assess its cache architecture.",
    try(var.profile.architecture.text_only, false) ? "" : "Text-only causal generation has not been established from model metadata.",
    try(var.profile.architecture.causal_generation, false) ? "" : "The model architecture has not established causal language generation; classifiers and unknown tasks cannot use this adapter.",
    local.single_host ? "" : "This P/D adapter requires PP=1 and one host per prefill/decode instance.",
    anytrue([for arg in try(var.serving.recipe.args, []) : can(regex("^--(kv-transfer-config|speculative-config|enable-expert-parallel)([.=]|$)", arg))]) ? "The recipe has a transfer, speculative or expert-parallel setting that this P/D adapter does not compose." : "",
    length(try(var.serving.recipe.companions, [])) == 0 ? "" : "The recipe requires companion processes that this P/D adapter does not provision.",
    contains(["auto", "bfloat16", "float16"], local.pd_kv_dtype) ? "" : "Quantized KV transfer requires scale compatibility that this P/D adapter has not assessed.",
    anytrue([for key in ["UCX_TLS", "VLLM_NIXL_SIDE_CHANNEL_HOST", "VLLM_NIXL_SIDE_CHANNEL_PORT"] : contains(keys(try(var.serving.recipe.env, {})), key)]) ? "The recipe overrides native P/D transport settings owned by this adapter." : "",
    anytrue([for arg in local.pd_args : can(regex("^--(hf-config-path|hf-overrides|config|task|runner|convert)([.=]|$)", arg))]) ? "Alternate config/task overrides need a separately assessed P/D profile." : ""
  ])
  assessment = {
    schema_version = "1.0", cache_layout = local.layout, requires_hma = local.requires_hma,
    routing_modes  = ["auto", "direct", "prefixaware"],
    lmcache_modes  = concat(["recipe", "disabled"], length(local.cache_reasons) == 0 ? ["mp"] : [], length(local.inprocess_reasons) == 0 ? ["inprocess"] : []),
    routing = {
      kvaware = {
        selectable     = false, status = "unavailable", reasons = local.kvaware_reasons,
        router_version = "0.1.14", evidence_url = "https://github.com/vllm-project/production-stack/issues/1208",
        enablement     = "Requires compatible engine cache events, exact request tokenization, all-group hybrid matching, and end-to-end routing validation."
      }
    },
    lmcache = {
      mp        = { selectable = length(local.cache_reasons) == 0, status = length(local.cache_reasons) == 0 ? "requires_image_validation" : "unsupported", reasons = local.cache_reasons },
      inprocess = { selectable = length(local.inprocess_reasons) == 0, status = length(local.inprocess_reasons) == 0 ? "requires_image_validation" : "unsupported", reasons = local.inprocess_reasons }
    },
    serving_modes = concat(["aggregated"], length(local.pd_reasons) == 0 ? ["disaggregated"] : []),
    disaggregation = {
      selectable   = length(local.pd_reasons) == 0, status = length(local.pd_reasons) == 0 ? "eligible_for_testing" : local.layout == "unverified" || !can(var.profile.architecture.text_only) || !can(var.profile.architecture.causal_generation) ? "unknown" : "unsupported_by_adapter",
      reasons      = local.pd_reasons, adapter = "native_nixl_v1", router_mode = "disaggregated_prefill_orchestrated",
      validation   = "Requires connector/image checks and observed KV transfer; recipe metadata alone is not runtime validation.",
      evidence_url = "https://docs.vllm.ai/en/v0.32.0/features/nixl_connector_compatibility/"
    },
    runtime_validation = "not_run; eligibility does not establish image, cache store/retrieve, or routing correctness"
  }
}
output "assessment" { value = local.assessment }
