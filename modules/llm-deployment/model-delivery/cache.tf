# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  # Deployment profiles extend the frozen upstream recipe without rewriting it.
  recipe_cache = try(local.serving.deployment_profile.lmcache, {})
  lmcache = {
    mode             = var.lmcache_mode == "recipe" ? try(local.recipe_cache.mode, lookup({ LMCacheMPConnector = "mp", LMCacheConnectorV1 = "inprocess" }, try(local.recipe_kv.kv_connector, ""), "disabled")) : var.lmcache_mode
    cpu_memory_gb    = coalesce(var.lmcache_cpu_memory_gb, try(local.recipe_cache.cpu_memory_gb, null), 8)
    chunk_size       = coalesce(var.lmcache_chunk_size, try(local.recipe_cache.chunk_size, null), 256)
    mamba_cache_mode = coalesce(var.lmcache_mamba_cache_mode, try(local.recipe_cache.mamba_cache_mode, null), "none")
  }
  recipe_args     = try(local.serving.recipe.args, [])
  recipe_kv_flags = [for arg in local.recipe_args : arg if arg == "--kv-transfer-config" || startswith(arg, "--kv-transfer-config=")]
  recipe_kv_text  = try(local.recipe_args[index(local.recipe_args, "--kv-transfer-config") + 1], trimprefix(one(local.recipe_kv_flags), "--kv-transfer-config="), "{}")
  recipe_kv       = try(jsondecode(local.recipe_kv_text), {})
  recipe_kv_compatible = try(
    length(local.recipe_kv_flags) == 1 && local.recipe_kv.kv_role == "kv_both" &&
    (local.lmcache.mode == "mp" ? (
      local.recipe_kv.kv_connector == "LMCacheMPConnector" &&
      local.recipe_kv.kv_connector_module_path == "lmcache.integration.vllm.lmcache_mp_connector" &&
      contains(["localhost", "127.0.0.1"], try(local.recipe_kv.kv_connector_extra_config["lmcache.mp.host"], "127.0.0.1")) &&
      tonumber(try(local.recipe_kv.kv_connector_extra_config["lmcache.mp.port"], 5555)) == 5555 &&
      alltrue([for key in keys(try(local.recipe_kv.kv_connector_extra_config, {})) : contains(["lmcache.mp.host", "lmcache.mp.port"], key)])
  ) : local.recipe_kv.kv_connector == "LMCacheConnectorV1" && !can(local.recipe_kv.kv_connector_module_path)), false)
  lmcache_enabled   = local.lmcache.mode != "disabled"
  routing_requested = var.routing_mode == "auto" ? try(local.serving.deployment_profile.routing.mode, "auto") : var.routing_mode
  routing_mode      = local.routing_requested == "auto" ? (var.router_enabled || tonumber(local.defaults.REPLICAS) > 1 || (var.autoscaling.enabled && var.autoscaling.max_replicas > 1) ? "prefixaware" : "direct") : local.routing_requested
  cache_memory_gib  = local.lmcache_enabled ? ceil(local.lmcache.cpu_memory_gb * 1e9 / pow(1024, 3)) * (local.lmcache.mode == "inprocess" ? tonumber(local.defaults.TP) : 1) + 4 : 0
  cache_args = !local.lmcache_enabled ? [] : concat(contains(try(local.serving.recipe.args, []), "--enable-prefix-caching") ? [] : ["--enable-prefix-caching"], length(local.recipe_kv_flags) > 0 ? [] : [
    "--kv-transfer-config", local.lmcache.mode == "mp" ? jsonencode({
      kv_connector              = "LMCacheMPConnector", kv_role = "kv_both"
      kv_connector_module_path  = "lmcache.integration.vllm.lmcache_mp_connector"
      kv_connector_extra_config = { "lmcache.mp.host" = "127.0.0.1", "lmcache.mp.port" = 5555 }
    }) : jsonencode({ kv_connector = "LMCacheConnectorV1", kv_role = "kv_both" })
  ], local.lmcache.mamba_cache_mode == "none" ? [] : ["--mamba-cache-mode", local.lmcache.mamba_cache_mode])
  cache_env = !local.lmcache_enabled ? {} : merge({
    LMCACHE_CHUNK_SIZE = tostring(local.lmcache.chunk_size),
    LMCACHE_LOCAL_CPU  = "True", LMCACHE_MAX_LOCAL_CPU_SIZE = tostring(local.lmcache.cpu_memory_gb)
    }, local.routing_mode != "kvaware" ? {} : {
    LMCACHE_ENABLE_CONTROLLER    = "True",
    PYTHONHASHSEED               = "123",
    LMCACHE_USE_EXPERIMENTAL     = "True",
    LMCACHE_CONTROLLER_PULL_URL  = "${local.name}-router-service:9000",
    LMCACHE_CONTROLLER_REPLY_URL = "${local.name}-router-service:9001",
    LMCACHE_LMCACHE_WORKER_PORTS = join(",", [for rank in range(tonumber(local.defaults.TP)) : tostring(8001 + rank)])
  })
}
resource "terraform_data" "cache_contract" {
  input = { cache = local.lmcache, routing = local.routing_mode }
  lifecycle {
    precondition {
      condition     = var.lmcache_mode != "disabled" || !contains(["LMCacheMPConnector", "LMCacheConnectorV1"], try(local.recipe_kv.kv_connector, ""))
      error_message = "The recipe itself enables LMCache. Remove its KV-transfer setting or select a complete alternate recipe before disabling the adapter."
    }
    precondition {
      condition     = !local.lmcache_enabled || length(local.recipe_kv_flags) == 0 || local.recipe_kv_compatible
      error_message = "Recipe KV transfer settings do not match this adapter. MP requires the external LMCache MP connector at localhost:5555 with kv_both; inprocess requires the native LMCacheConnectorV1. Conflicting or duplicate flags are not overwritten."
    }
    precondition {
      condition     = !local.lmcache_enabled || local.lmcache.mamba_cache_mode == "none" || !anytrue([for arg in try(local.serving.recipe.args, []) : startswith(arg, "--mamba-cache-mode")])
      error_message = "Mamba cache policy is already set by the recipe; keep it there or set it in the deployment profile, not both."
    }
    precondition {
      condition     = local.routing_mode != "kvaware" || try(local.serving.recipe.env.PYTHONHASHSEED, "123") == "123"
      error_message = "The pinned KV-aware controller requires the same PYTHONHASHSEED=123 in serving workers and router."
    }
    precondition {
      condition     = contains(["disabled", "mp", "inprocess"], local.lmcache.mode) && contains(["direct", "prefixaware", "kvaware"], local.routing_mode)
      error_message = "Recipe deployment profile contains an unsupported LMCache or routing mode."
    }
    precondition {
      condition     = local.routing_mode != "direct" || (!var.router_enabled && tonumber(local.defaults.REPLICAS) == 1 && (!var.autoscaling.enabled || var.autoscaling.max_replicas == 1))
      error_message = "Direct routing requires one replica, no scale-out and router_enabled=false."
    }
    precondition {
      condition     = local.routing_mode != "kvaware" || local.lmcache.mode == "inprocess"
      error_message = "The pinned production-stack KV-aware router requires the inprocess LMCache controller protocol. MP uses a different coordinator protocol; choose prefixaware with MP."
    }
    precondition {
      condition     = !local.lmcache_enabled || tonumber(local.defaults.HOSTS_PER_REPLICA) == 1
      error_message = "This LMCache adapter supports single-host TP only. Multi-host PP requires a separately assessed cache layout."
    }
    precondition {
      condition     = !local.lmcache_enabled || (local.lmcache.cpu_memory_gb > 0 && local.lmcache.chunk_size >= 1 && floor(local.lmcache.chunk_size) == local.lmcache.chunk_size && contains(["none", "align"], local.lmcache.mamba_cache_mode))
      error_message = "LMCache needs positive host RAM, an integer chunk size and a supported Mamba cache mode."
    }
    precondition {
      condition     = !local.lmcache_enabled || alltrue([for arg in try(local.serving.recipe.args, []) : !can(regex("^--no-enable-prefix-caching(=|$)", arg))])
      error_message = "LMCache adapter settings conflict with raw recipe cache flags; resolve them in one deployment profile before Apply."
    }
    precondition {
      condition     = !local.lmcache_enabled || !anytrue([for key in keys(try(local.serving.recipe.env, {})) : startswith(key, "LMCACHE_")])
      error_message = "LMCache adapter configuration conflicts with raw recipe LMCACHE environment overrides."
    }
  }
}
