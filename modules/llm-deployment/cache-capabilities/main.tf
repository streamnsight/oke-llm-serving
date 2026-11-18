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
    runtime_validation = "not_run; eligibility does not establish image, cache store/retrieve, or routing correctness"
  }
}
output "assessment" { value = local.assessment }
