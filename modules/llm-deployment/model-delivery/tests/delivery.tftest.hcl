# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
  mock_resource "oci_devops_deployment" { defaults = { state = "SUCCEEDED" } }
  mock_data "oci_objectstorage_namespace" { defaults = { namespace = "fixture" } }
  mock_data "oci_core_subnet" { defaults = { compartment_id = "network-compartment" } }
}
mock_provider "oci" { alias = "home" }
variables {
  tenancy_ocid   = "tenancy"
  compartment_id = "workloads"
  name           = "qwen"
  platform = {
    platform_name          = "fixture", generation = "platform-generation", region = "eu-frankfurt-1", cluster_id = "cluster",
    cluster_compartment_id = "cluster-compartment", compartment_id = "workloads", kubernetes_version = "v1.34.1",
    project_id             = "project", deploy_environment_id = "oke-environment", script_repository_id = "source", result_repository_id = "results",
    runner_subnet_id       = "subnet", runner_nsg_ids = [], allocation = { gpu_pool_id = "gpu-pool" },
    gpu_selector           = "oke-llm/allocation=fixture", gpu_shape = "BM.GPU4.8", node_count = 1, gpu_count_per_host = 8,
    transport              = { requires_rdma = false }, required_components = ["lws", "prometheus"],
    monitoring_enabled     = true, model_onboarding_pipeline_id = "trusted-onboarding"
  }
  model = {
    schema_version = "1.0", kind = "llm_model", selection_id = "option-1",
    model          = { repository = "org/model", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", checkpoint_download_bytes = 21474836480 },
    profile        = { memory = { assumptions = { context_length = 4096, concurrency = 8 } } },
    selection = {
      tensor_parallel_size = 2, pipeline_parallel_size = 1, replicas = 4,
      serving_configuration = {
        model  = { repository = "org/model", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
        engine = { framework = "vllm", image = "vllm/vllm-openai@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", multi_node_backend = "mp" },
        recipe = { args = ["--reasoning-parser", "qwen3", "--tool-call-parser", "qwen3_coder", "--kv-cache-dtype", "fp8", "--dtype", "bfloat16"], env = { VLLM_USE_RUST_FRONTEND = "1", CUDA_MODULE_LOADING = "LAZY" } }
      }
    }
  }
}
run "model_delivery_deploys_and_validates_automatically" {
  command = apply
  assert {
    condition     = length(output.all_pipeline_ids) == 4 && output.model_delivery.automatically_started && !output.model_delivery.automatic_execution.benchmark_automatically_started && !output.model_delivery.responses_conversation_persistence
    error_message = "Apply must deploy and validate while keeping benchmark manual and not claiming durable conversations."
  }
  assert {
    condition     = output.model_delivery.project_id == "project" && output.model_delivery.cluster_id == "cluster" && output.model_delivery.onboarding.pipeline_id == "trusted-onboarding"
    error_message = "Reuse the exact trusted infrastructure project, environment and onboarding path."
  }
  assert {
    condition     = local.values.recipeArgs == var.model.selection.serving_configuration.recipe.args && local.values.recipeEnv == merge(var.model.selection.serving_configuration.recipe.env, { VLLM_USE_RUST_FRONTEND = "$${VLLM_USE_RUST_FRONTEND}" }) && local.values.nodeSelector["oke-llm/allocation"] == "fixture"
    error_message = "Frozen argv and all non-frontend env remain intact; only the frontend gets a named editable deployment parameter."
  }
  assert {
    condition     = local.defaults.VLLM_USE_RUST_FRONTEND == "0" && local.config.serving.recipe.env == merge(var.model.selection.serving_configuration.recipe.env, { VLLM_USE_RUST_FRONTEND = "0" }) && local.serving.recipe.env == var.model.selection.serving_configuration.recipe.env
    error_message = "Python must override a recipe's experimental Rust opt-in in the effective config while preserving raw recipe provenance and other environment values."
  }
  assert {
    condition     = local.defaults.MODEL_REVISION == var.model.selection.serving_configuration.model.resolved_revision
    error_message = "Discovery's immutable commit remains the model deployment default."
  }
  assert {
    condition     = local.defaults.SERVING_IMAGE == "docker.io/${var.model.selection.serving_configuration.engine.image}" && local.values["vllm-stack"].routerSpec.repository == "docker.io/lmcache/lmstack-router" && startswith(local.config.benchmark_image, "docker.io/vllm/vllm-openai-cpu@sha256:")
    error_message = "Frozen short image names, router and CPU benchmark must have explicit registries without changing image digests."
  }
  assert {
    condition     = local.router_enabled && local.workspace_gib >= 28 && local.values["vllm-stack"].servingEngineSpec.enableEngine == false && local.values["vllm-stack"].routerSpec.extraArgs[1] == "oke-llm/model=${local.identity},oke-llm/endpoint=true"
    error_message = "Packed replicas need a literal leader-only prefix-aware router and a full checkpoint workspace PER POD."
  }
  assert {
    condition     = alltrue([for rule in oci_identity_policy.model.statements : !strcontains(rule, "CLUSTER_MANAGE") && !strcontains(rule, "cluster-family") && !strcontains(rule, "instance-family") && !strcontains(rule, "manage clusters") && !strcontains(rule, "manage objects")])
    error_message = "Model runtime identities may not administer clusters, node pools, GPU instances or buckets."
  }
  assert {
    condition     = alltrue([for operation, spec in local.operation_specs : length(yamldecode(spec).inputArtifacts) == 2 && yamldecode(spec).env.variables.MODEL_NAMESPACE == "$${MODEL_NAMESPACE}" && toset([for input in yamldecode(spec).inputArtifacts : input.location]) == toset(["./runtime/common.sh", "./runtime/config.json"]) && alltrue([for path in ["common.sh", "config.json"] : anytrue([for input in yamldecode(spec).inputArtifacts : input.path == module.delivery.runtime_artifacts[path].artifact_path && input.version == module.delivery.runtime_artifacts[path].version])]) && module.inline_operation[operation].byte_size <= 51200 && strcontains(module.inline_operation[operation].preparation_command, "cat > 'runtime/operation.sh'")]) && alltrue([for operation, artifact in oci_devops_deploy_artifact.operation : artifact.deploy_artifact_source[0].deploy_artifact_source_type == "INLINE" && artifact.deploy_artifact_source[0].base64encoded_content == module.inline_operation[operation].content]) && !contains(keys(local.operation_shared_files), "common.sh") && !contains(keys(local.operation_files.validate), "benchmark.sh") && !contains(keys(local.operation_files.benchmark), "validate.sh") && output.onboarding_arguments.MODEL_NAMESPACE == output.namespace
    error_message = "Operations must reuse existing inputs, remain readable and fit the raw-content byte limit. Payload sizes: ${jsonencode({ for operation, spec in module.inline_operation : operation => { decoded_bytes = spec.byte_size, encoded_characters = spec.encoded_size } })}"
  }
}
run "explicit_Rust_frontend_is_opt_in" {
  command = plan
  variables { api_frontend = "rust" }
  assert {
    condition     = local.defaults.VLLM_USE_RUST_FRONTEND == "1" && local.config.serving.recipe.env.VLLM_USE_RUST_FRONTEND == "1" && local.config.serving.recipe.env.CUDA_MODULE_LOADING == "LAZY"
    error_message = "Rust frontend is available only by explicit selection; unrelated recipe environment remains unchanged."
  }
}
run "main_is_an_explicit_direct_Hub_override" {
  command = plan
  variables { overrides = { model_revision = "main" } }
  assert {
    condition     = local.defaults.MODEL_REVISION == "main" && local.defaults.SERVING_IMAGE == "docker.io/${var.model.selection.serving_configuration.engine.image}" && local.values.recipeArgs == var.model.selection.serving_configuration.recipe.args && var.model.model.revision == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    error_message = "An explicit main ref is accepted for direct Hub delivery without rewriting discovery's commit, the serving image or recipe argv."
  }
}
run "main_is_not_an_immutable_PVC_snapshot" {
  command = plan
  variables {
    overrides = { model_revision = "main" }
    storage   = { mode = "existing_pvc", pvc_name = "retained-weights" }
  }
  expect_failures = [terraform_data.contract]
}
run "main_is_not_a_staged_snapshot" {
  command = plan
  variables {
    overrides = { model_revision = "main" }
    storage   = { mode = "staged_object_storage", pvc_name = "retained-weights" }
  }
  expect_failures = [terraform_data.contract]
}
run "other_mutable_refs_are_rejected" {
  command = plan
  variables { overrides = { model_revision = "refs/heads/main" } }
  expect_failures = [terraform_data.contract]
}
run "unknown_frontend_is_rejected" {
  command = plan
  variables { api_frontend = "automatic" }
  expect_failures = [var.api_frontend]
}
run "multi_node_preserves_separate_host_geometry" {
  command = plan
  variables { overrides = { pipeline_parallel_size = 2, hosts_per_replica = 2, replicas = 1 } }
  assert {
    condition     = local.defaults.HOSTS_PER_REPLICA == "2" && local.defaults.PP == "2" && local.defaults.GPUS_PER_POD == "2" && !contains(keys(module.delivery.component_pipeline_ids), "lws")
    error_message = "Model delivery targets existing shared controllers and retains explicit host versus per-host GPU geometry."
  }
}
run "candidate_uses_frozen_fallback_without_dropping_recipe" {
  command = plan
  variables {
    model = merge(var.model, {
      serving_configuration = var.model.selection.serving_configuration,
      selection             = { tensor_parallel_size = 2, pipeline_parallel_size = 1, replicas = 4, engine = var.model.selection.serving_configuration.engine }
    })
  }
  assert {
    condition     = local.values.recipeArgs == var.model.serving_configuration.recipe.args && local.defaults.SERVING_IMAGE == "docker.io/${var.model.serving_configuration.engine.image}"
    error_message = "Analytical candidates without nested serving_configuration must retain their frozen top-level recipe/image fallback."
  }
}
run "short_override_uses_Docker_Hub" {
  command = plan
  variables { overrides = { serving_image = "custom/engine@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
  assert {
    condition     = local.defaults.SERVING_IMAGE == "docker.io/custom/engine@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    error_message = "An expert override follows the same registry normalization as a frozen recipe."
  }
}
run "bare_override_uses_official_Docker_Hub_namespace" {
  command = plan
  variables { overrides = { serving_image = "engine@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
  assert {
    condition     = local.defaults.SERVING_IMAGE == "docker.io/library/engine@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    error_message = "A one-segment Docker image name must use the official library namespace, even though its digest contains a colon."
  }
}
run "qualified_override_is_unchanged" {
  command = plan
  variables { overrides = { serving_image = "ghcr.io/custom/engine@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
  assert {
    condition     = local.defaults.SERVING_IMAGE == var.overrides.serving_image
    error_message = "An explicit custom registry and immutable digest must be preserved."
  }
}
run "Docker_Hub_override_is_not_prefixed_twice" {
  command = plan
  variables { overrides = { serving_image = "docker.io/custom/engine@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
  assert {
    condition     = local.defaults.SERVING_IMAGE == var.overrides.serving_image
    error_message = "An already qualified Docker Hub override must not be prefixed twice."
  }
}
run "OCIR_override_is_unchanged" {
  command = plan
  variables { overrides = { serving_image = "fra.ocir.io/tenancy/engine@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
  assert {
    condition     = local.defaults.SERVING_IMAGE == var.overrides.serving_image
    error_message = "OCIR tenancy/repository paths and digests must remain unchanged."
  }
}
run "localhost_with_port_override_is_unchanged" {
  command = plan
  variables { overrides = { serving_image = "localhost:5000/custom/engine@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
  assert {
    condition     = local.defaults.SERVING_IMAGE == var.overrides.serving_image
    error_message = "A registry port must not be mistaken for a Docker Hub namespace."
  }
}
run "localhost_without_port_override_is_unchanged" {
  command = plan
  variables { overrides = { serving_image = "localhost/custom/engine@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
  assert {
    condition     = local.defaults.SERVING_IMAGE == var.overrides.serving_image
    error_message = "Docker's special localhost registry name must remain unchanged."
  }
}
run "unknown_checkpoint_does_not_block_pipeline_creation" {
  command = plan
  variables { model = merge(var.model, { model = merge(var.model.model, { checkpoint_download_bytes = null }) }) }
  assert {
    condition     = local.snapshot_bytes == null && !local.config.storage.workspace_explicit && local.workspace_gib == 64
    error_message = "Unknown sizing is an explicit execution-time validation requirement, not a fabricated weight count or an attribute crash."
  }
}

run "installed_KEDA_does_not_enable_model_autoscaling" {
  command = plan
  variables { platform = merge(var.platform, { required_components = ["lws", "prometheus", "keda"] }) }
  assert {
    condition     = !local.values.autoscaling.enabled && !local.config.autoscaling.enabled
    error_message = "Installing the shared KEDA capability must not create a model scaling policy."
  }
}
run "model_can_opt_into_autoscaling_with_existing_controllers" {
  command = plan
  variables {
    platform    = merge(var.platform, { monitoring_enabled = false, required_components = ["lws", "prometheus", "keda"] })
    autoscaling = { enabled = true, min_replicas = 1, max_replicas = 2, prometheus_url = "http://prometheus.monitoring.svc:9090" }
  }
  assert {
    condition     = local.values.autoscaling.enabled && local.values.monitoring.enabled && local.config.autoscaling.max_replicas == 2
    error_message = "The model's opt-in owns scaling; no infrastructure autoscaling flag is required."
  }
}
run "model_autoscaling_rejects_missing_shared_KEDA" {
  command = plan
  variables { autoscaling = { enabled = true, prometheus_url = "http://prometheus.monitoring.svc:9090" } }
  expect_failures = [terraform_data.contract]
}

run "routine_validation_has_no_artifact_report_binding" {
  command = plan
  assert {
    condition     = alltrue([for spec in values(local.operation_specs) : !contains(keys(yamldecode(spec).env.variables), "DELIVERY_RESULT_REPOSITORY")]) && yamldecode(local.operation_specs.benchmark).timeoutInSeconds == 21600 && yamldecode(local.operation_specs.validate).timeoutInSeconds == 3600 && local.operation_parameters.BENCHMARK_REQUESTS == "auto" && local.operation_parameters.BENCHMARK_PREFIX_TOKENS == "auto" && !anytrue([for statement in oci_identity_policy.model.statements : strcontains(statement, "manage generic-artifacts")])
    error_message = "Validation and benchmark summaries use DevOps logs without result-repository bindings or artifact-write IAM; only manual benchmark receives the longer deadline."
  }
}

run "lmcache_mp_is_local_and_budgeted" {
  command = plan
  variables {
    lmcache_mode          = "mp"
    lmcache_cpu_memory_gb = 8
    routing_mode          = "prefixaware"
  }
  assert {
    condition     = local.lmcache_enabled && local.values.memory == "28Gi" && local.values.lmcache.mode == "mp" && local.routing_mode == "prefixaware" && contains(local.values.recipeArgs, "--kv-transfer-config")
    error_message = "MP cache must be rendered with its host-RAM budget and explicit routing mode."
  }
  assert {
    condition     = jsondecode(local.cache_args[2]).kv_connector_extra_config["lmcache.mp.host"] == "127.0.0.1" && jsondecode(local.cache_args[2]).kv_connector == "LMCacheMPConnector"
    error_message = "MP workers must use the explicitly selected external connector and local cache process."
  }
}
run "legacy_controller_wiring_is_not_proof_of_KV_routing" {
  command = plan
  variables {
    lmcache_mode = "inprocess"
    routing_mode = "kvaware"
  }
  expect_failures = [terraform_data.cache_contract]
}
run "mp_cannot_claim_legacy_controller_routing" {
  command = plan
  variables {
    lmcache_mode = "mp"
    routing_mode = "kvaware"
  }
  expect_failures = [terraform_data.cache_contract]
}
run "direct_rejects_scaleout" {
  command = plan
  variables { routing_mode = "direct" }
  expect_failures = [terraform_data.cache_contract]
}
run "direct_single_replica" {
  command = plan
  variables {
    routing_mode = "direct"
    overrides    = { replicas = 1 }
  }
  assert {
    condition     = !local.router_enabled && local.routing_mode == "direct"
    error_message = "Explicit direct mode must preserve the one-replica path."
  }
}
run "lmcache_rejects_unbounded_buffer" {
  command = plan
  variables {
    lmcache_mode          = "mp"
    lmcache_cpu_memory_gb = 0
  }
  expect_failures = [terraform_data.cache_contract]
}
run "lmcache_rejects_unassessed_multihost" {
  command = plan
  variables {
    lmcache_mode = "mp"
    overrides    = { hosts_per_replica = 2, pipeline_parallel_size = 2 }
  }
  expect_failures = [terraform_data.cache_contract]
}
run "recipe_deployment_profile_selects_cache_and_routing" {
  command = plan
  variables {
    model = {
      schema_version = "1.0", kind = "llm_model", selection_id = "profile",
      model          = { repository = "org/model", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", checkpoint_download_bytes = 21474836480 },
      profile        = { memory = { assumptions = { context_length = 4096, concurrency = 8 } } },
      selection = {
        tensor_parallel_size = 2, pipeline_parallel_size = 1, replicas = 1,
        serving_configuration = {
          model              = { repository = "org/model", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
          engine             = { framework = "vllm", image = "vllm/vllm-openai@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" },
          recipe             = { args = ["--enable-prefix-caching"], env = {} },
          deployment_profile = { lmcache = { mode = "mp", cpu_memory_gb = 12, chunk_size = 128, mamba_cache_mode = "align" }, routing = { mode = "prefixaware" } }
        }
      }
    }
  }
  assert {
    condition     = local.lmcache.mode == "mp" && local.lmcache.cpu_memory_gb == 12 && local.lmcache.chunk_size == 128 && local.router_enabled && contains(local.cache_args, "align") && length([for arg in local.values.recipeArgs : arg if arg == "--enable-prefix-caching"]) == 1
    error_message = "Frozen recipe deployment recommendations must reach the workload without manual installs or tfvars."
  }
}

run "existing_recipe_cache_arguments_are_preserved_once" {
  command = plan
  variables { model = jsondecode("{\"schema_version\": \"1.0\", \"kind\": \"llm_model\", \"selection_id\": \"native-cache\", \"model\": {\"repository\": \"org/generic-attention\", \"revision\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\", \"checkpoint_download_bytes\": 21474836480}, \"profile\": {\"memory\": {\"assumptions\": {\"context_length\": 4096, \"concurrency\": 4}}}, \"selection\": {\"tensor_parallel_size\": 1, \"pipeline_parallel_size\": 1, \"replicas\": 1, \"serving_configuration\": {\"model\": {\"repository\": \"org/generic-attention\", \"resolved_revision\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}, \"engine\": {\"framework\": \"vllm\", \"image\": \"vllm/vllm-openai@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"}, \"recipe\": {\"args\": [\"--enable-prefix-caching\", \"--kv-transfer-config={\\\"kv_connector\\\": \\\"LMCacheMPConnector\\\", \\\"kv_role\\\": \\\"kv_both\\\", \\\"kv_connector_module_path\\\": \\\"lmcache.integration.vllm.lmcache_mp_connector\\\", \\\"kv_connector_extra_config\\\": {\\\"lmcache.mp.host\\\": \\\"127.0.0.1\\\", \\\"lmcache.mp.port\\\": 5555}}\"], \"env\": {}}, \"deployment_profile\": {\"lmcache\": {\"mode\": \"mp\"}, \"routing\": {\"mode\": \"prefixaware\"}}}}}") }
  assert {
    condition     = local.recipe_kv_compatible && length(local.recipe_kv_flags) == 1 && !contains(local.cache_args, "--kv-transfer-config") && length([for arg in local.values.recipeArgs : arg if arg == "--enable-prefix-caching"]) == 1
    error_message = "Compatible native recipe cache settings must be preserved rather than duplicated or overwritten."
  }
}

run "foreign_recipe_cache_endpoint_is_not_silently_overridden" {
  command = plan
  variables { model = jsondecode("{\"schema_version\": \"1.0\", \"kind\": \"llm_model\", \"selection_id\": \"native-cache\", \"model\": {\"repository\": \"org/generic-attention\", \"revision\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\", \"checkpoint_download_bytes\": 21474836480}, \"profile\": {\"memory\": {\"assumptions\": {\"context_length\": 4096, \"concurrency\": 4}}}, \"selection\": {\"tensor_parallel_size\": 1, \"pipeline_parallel_size\": 1, \"replicas\": 1, \"serving_configuration\": {\"model\": {\"repository\": \"org/generic-attention\", \"resolved_revision\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}, \"engine\": {\"framework\": \"vllm\", \"image\": \"vllm/vllm-openai@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"}, \"recipe\": {\"args\": [\"--enable-prefix-caching\", \"--kv-transfer-config={\\\"kv_connector\\\": \\\"LMCacheMPConnector\\\", \\\"kv_role\\\": \\\"kv_both\\\", \\\"kv_connector_module_path\\\": \\\"lmcache.integration.vllm.lmcache_mp_connector\\\", \\\"kv_connector_extra_config\\\": {\\\"lmcache.mp.host\\\": \\\"foreign.example\\\", \\\"lmcache.mp.port\\\": 5555}}\"], \"env\": {}}, \"deployment_profile\": {\"lmcache\": {\"mode\": \"mp\"}, \"routing\": {\"mode\": \"prefixaware\"}}}}}") }
  expect_failures = [terraform_data.cache_contract]
}

run "native_lmcache_recipe_is_detected_without_a_model_specific_profile" {
  command = plan
  variables { model = jsondecode("{\"schema_version\": \"1.0\", \"kind\": \"llm_model\", \"selection_id\": \"native-cache\", \"model\": {\"repository\": \"org/generic-attention\", \"revision\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\", \"checkpoint_download_bytes\": 21474836480}, \"profile\": {\"memory\": {\"assumptions\": {\"context_length\": 4096, \"concurrency\": 4}}}, \"selection\": {\"tensor_parallel_size\": 1, \"pipeline_parallel_size\": 1, \"replicas\": 1, \"serving_configuration\": {\"model\": {\"repository\": \"org/generic-attention\", \"resolved_revision\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}, \"engine\": {\"framework\": \"vllm\", \"image\": \"vllm/vllm-openai@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"}, \"recipe\": {\"args\": [\"--enable-prefix-caching\", \"--kv-transfer-config={\\\"kv_connector\\\": \\\"LMCacheMPConnector\\\", \\\"kv_role\\\": \\\"kv_both\\\", \\\"kv_connector_module_path\\\": \\\"lmcache.integration.vllm.lmcache_mp_connector\\\", \\\"kv_connector_extra_config\\\": {\\\"lmcache.mp.host\\\": \\\"127.0.0.1\\\", \\\"lmcache.mp.port\\\": 5555}}\"], \"env\": {}}}}}") }
  assert {
    condition     = local.lmcache.mode == "mp" && local.lmcache_enabled && local.recipe_kv_compatible
    error_message = "Recognized native recipe connectors should select the generic adapter without model-specific conditions."
  }
}

run "disabled_does_not_silently_leave_recipe_lmcache_running" {
  command = plan
  variables {
    model        = jsondecode("{\"schema_version\": \"1.0\", \"kind\": \"llm_model\", \"selection_id\": \"native-cache\", \"model\": {\"repository\": \"org/generic-attention\", \"revision\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\", \"checkpoint_download_bytes\": 21474836480}, \"profile\": {\"memory\": {\"assumptions\": {\"context_length\": 4096, \"concurrency\": 4}}}, \"selection\": {\"tensor_parallel_size\": 1, \"pipeline_parallel_size\": 1, \"replicas\": 1, \"serving_configuration\": {\"model\": {\"repository\": \"org/generic-attention\", \"resolved_revision\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}, \"engine\": {\"framework\": \"vllm\", \"image\": \"vllm/vllm-openai@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"}, \"recipe\": {\"args\": [\"--enable-prefix-caching\", \"--kv-transfer-config={\\\"kv_connector\\\": \\\"LMCacheMPConnector\\\", \\\"kv_role\\\": \\\"kv_both\\\", \\\"kv_connector_module_path\\\": \\\"lmcache.integration.vllm.lmcache_mp_connector\\\", \\\"kv_connector_extra_config\\\": {\\\"lmcache.mp.host\\\": \\\"127.0.0.1\\\", \\\"lmcache.mp.port\\\": 5555}}\"], \"env\": {}}}}}")
    lmcache_mode = "disabled"
  }
  expect_failures = [terraform_data.cache_contract]
}
run "hybrid_cache_requirement_is_derived_without_model_name_rules" {
  command = plan
  variables {
    lmcache_mode = "inprocess"
    routing_mode = "kvaware"
    model        = merge(var.model, { profile = merge(var.model.profile, { architecture = { kind = "hybrid_dense", attention = { layer_types = ["full_attention", "linear_attention"] } } }) })
  }
  expect_failures = [terraform_data.cache_contract]
  assert {
    condition     = local.values.lmcache.requires_hma && local.config.lmcache.requires_hma && local.values["vllm-stack"].routerSpec.startupProbe.periodSeconds * local.values["vllm-stack"].routerSpec.startupProbe.failureThreshold >= 180
    error_message = "The selected image must verify hybrid connector capability before loading weights, and the router needs a bounded cold-start budget."
  }
}
run "ordinary_models_do_not_require_hybrid_connector_capability" {
  command = plan
  variables {
    lmcache_mode = "inprocess"
    routing_mode = "prefixaware"
    model        = merge(var.model, { profile = merge(var.model.profile, { architecture = { kind = "dense" } }) })
  }
  assert {
    condition     = !local.values.lmcache.requires_hma
    error_message = "Ordinary models must not be rejected by hybrid-only capability checks."
  }
}
run "unknown_layout_cannot_select_inprocess_offload" {
  command = plan
  variables { lmcache_mode = "inprocess" }
  expect_failures = [terraform_data.cache_contract]
}
