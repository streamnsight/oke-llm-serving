# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
  mock_data "oci_objectstorage_namespace" { defaults = { namespace = "fixture" } }
  mock_data "oci_core_subnet" { defaults = { compartment_id = "network-compartment" } }
}
mock_provider "oci" { alias = "home" }
variables {
  tenancy_ocid   = "tenancy"
  compartment_id = "workloads"
  name           = "qwen"
  platform = {
    platform_name = "fixture", generation = "platform-generation", region = "eu-frankfurt-1", cluster_id = "cluster",
    cluster_compartment_id = "cluster-compartment", compartment_id = "workloads", kubernetes_version = "v1.34.1",
    project_id = "project", deploy_environment_id = "oke-environment", script_repository_id = "source", result_repository_id = "results",
    runner_subnet_id = "subnet", runner_nsg_ids = [], allocation = { gpu_pool_id = null },
    gpu_selector = "oke-llm/allocation=fixture", gpu_shape = "BM.GPU4.8", node_count = 1, gpu_count_per_host = 8,
    transport = { requires_rdma = false }, required_components = ["lws", "prometheus"],
    monitoring_enabled = true, autoscaling_enabled = false, model_onboarding_pipeline_id = "trusted-onboarding"
  }
  model = {
    schema_version = "1.0", kind = "llm_model", selection_id = "option-1",
    model = { repository = "org/model", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", checkpoint_download_bytes = 21474836480 },
    profile = { memory = { assumptions = { context_length = 4096, concurrency = 8 } } },
    selection = {
      tensor_parallel_size = 2, pipeline_parallel_size = 1, replicas = 4,
      serving_configuration = {
        model = { repository = "org/model", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
        engine = { framework = "vllm", image = "vllm/vllm-openai@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", multi_node_backend = "mp" },
        recipe = { args = ["--reasoning-parser", "qwen3", "--tool-call-parser", "qwen3_coder", "--kv-cache-dtype", "fp8", "--dtype", "bfloat16"], env = { VLLM_USE_RUST_FRONTEND = "1" } }
      }
    }
  }
}
run "cpu_debug_creates_model_only_delivery" {
  command = apply
  assert {
    condition     = length(output.all_pipeline_ids) == 4 && output.model_delivery.automatically_started == false && !output.model_delivery.responses_conversation_persistence
    error_message = "Create explicit deploy/validate/benchmark/undeploy pipelines without launching workloads or claiming durable conversations."
  }
  assert {
    condition     = output.model_delivery.project_id == "project" && output.model_delivery.cluster_id == "cluster" && output.model_delivery.onboarding.pipeline_id == "trusted-onboarding"
    error_message = "Reuse the exact trusted infrastructure project, environment and onboarding path."
  }
  assert {
    condition     = local.values.recipeArgs == var.model.selection.serving_configuration.recipe.args && local.values.recipeEnv == var.model.selection.serving_configuration.recipe.env && local.values.nodeSelector["oke-llm/allocation"] == "fixture"
    error_message = "Frozen flags/env and the infrastructure allocation selector must survive without rebuilding parser/dtype/KV arguments."
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
    condition     = alltrue([for spec in values(local.operation_specs) : length(yamldecode(spec).inputArtifacts) > 3 && yamldecode(spec).env.variables.MODEL_NAMESPACE == "$${MODEL_NAMESPACE}"]) && output.onboarding_arguments.MODEL_NAMESPACE == output.namespace
    error_message = "Operations use file artifacts and expose the immutable namespace parameter for trusted onboarding."
  }
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
      selection = { tensor_parallel_size = 2, pipeline_parallel_size = 1, replicas = 4, engine = var.model.selection.serving_configuration.engine }
    })
  }
  assert {
    condition = local.values.recipeArgs == var.model.serving_configuration.recipe.args && local.defaults.SERVING_IMAGE == var.model.serving_configuration.engine.image
    error_message = "Analytical candidates without nested serving_configuration must retain their frozen top-level recipe/image fallback."
  }
}
run "unknown_checkpoint_does_not_block_pipeline_creation" {
  command = plan
  variables { model = merge(var.model, { model = merge(var.model.model, { checkpoint_download_bytes = null }) }) }
  assert {
    condition = local.snapshot_bytes == null && !local.config.storage.workspace_explicit && local.workspace_gib == 64
    error_message = "Unknown sizing is an explicit execution-time validation requirement, not a fabricated weight count or an attribute crash."
  }
}
