# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
  mock_resource "oci_devops_deployment" { defaults = { state = "SUCCEEDED" } }
  mock_data "oci_objectstorage_namespace" { defaults = { namespace = "fixture" } }
  mock_data "oci_core_subnet" { defaults = { compartment_id = "network-compartment" } }
}
run "native_PD_renders_role_configuration_without_LMCache" {
  command = plan
  assert {
    condition     = local.values.disaggregation.enabled && local.values.disaggregation.prefillReplicas == 1 && local.routing_mode == "disaggregated_prefill_orchestrated" && local.router_enabled && !local.lmcache_enabled && local.config.model.selection.platform_plan.topology.strategy == "native_pd" && contains(local.values["vllm-stack"].routerSpec.extraArgs, "--prefill-model-labels") && contains(keys(local.runtime_files), "pd_observe.py") && contains(keys(local.operation_input_files), "pd_observe.py")
    error_message = "Explicit native P/D must create role pools and orchestration independently from the LMCache controller."
  }
}
run "native_PD_startup_budget_reaches_chart_and_runtime" {
  command = plan
  variables { timeout_seconds = 901 }
  assert {
    condition     = local.values.startupTimeoutSeconds == 901 && local.config.timeout_seconds == 901
    error_message = "The configured readiness budget must reach both the model chart and runtime validation."
  }
}
run "native_PD_counts_both_role_pools" {
  command = plan
  variables {
    overrides        = { replicas = 3 }
    prefill_replicas = 2
  }
  assert {
    condition     = local.runtime_node_count == 2 && local.pd.prefill_replicas == 2 && local.defaults.REPLICAS == "3"
    error_message = "Five TP=2 instances need ten GPUs/two eight-GPU hosts, not only the six decode GPUs."
  }
}
run "native_PD_rejects_PP_before_deployment" {
  command = plan
  variables { overrides = { replicas = 1, pipeline_parallel_size = 2, hosts_per_replica = 2 } }
  expect_failures = [terraform_data.pd_contract]
}
run "native_PD_cannot_reuse_metadata_for_another_model" {
  command = plan
  variables { overrides = { replicas = 1, model_id = "different/model" } }
  expect_failures = [terraform_data.pd_contract]
}
run "native_PD_rejects_incompatible_router_override" {
  command = plan
  variables { routing_mode = "prefixaware" }
  expect_failures = [terraform_data.pd_contract]
}
run "native_PD_does_not_silently_compose_MP_offloading" {
  command = plan
  variables { lmcache_mode = "mp" }
  expect_failures = [terraform_data.pd_contract]
}
mock_provider "oci" { alias = "home" }
variables {
  serving_mode   = "disaggregated"
  overrides      = { replicas = 1 }
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
    profile        = { architecture = { kind = "dense", text_only = true, causal_generation = true, attention = { layout = "uniform_attention", layer_types = ["full_attention"] } }, memory = { assumptions = { context_length = 4096, concurrency = 8 } } },
    selection = {
      tensor_parallel_size = 2, pipeline_parallel_size = 1, replicas = 4,
      serving_configuration = {
        model  = { repository = "org/model", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
        engine = { framework = "vllm", image = "vllm/vllm-openai@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", multi_node_backend = "mp" },
        recipe = { args = ["--reasoning-parser", "qwen3", "--tool-call-parser", "qwen3_coder", "--dtype", "bfloat16"], env = { VLLM_USE_RUST_FRONTEND = "1", CUDA_MODULE_LOADING = "LAZY" } }
      }
    }
  }
}
