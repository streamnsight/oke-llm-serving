# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
  mock_data "oci_objectstorage_namespace" { defaults = { namespace = "fixture" } }
  mock_data "oci_core_subnet" { defaults = { compartment_id = "network-compartment" } }
  mock_resource "oci_devops_deployment" { defaults = { state = "SUCCEEDED" } }
}
mock_provider "oci" { alias = "home" }
variables {
  tenancy_ocid   = "tenancy"
  compartment_id = "workloads"
  name           = "qwen"
  platform = {
    binding_mode                 = "runtime", platform_name = "fixture", generation = "platform-generation", region = "eu-frankfurt-1", cluster_id = "cluster",
    cluster_compartment_id       = "cluster-compartment", compartment_id = "workloads", kubernetes_version = "v1.34.1",
    project_id                   = "project", deploy_environment_id = "oke-environment", script_repository_id = "source", result_repository_id = "results",
    runner_subnet_id             = "subnet", runner_nsg_ids = [], allocation = { gpu_pool_id = "gpu-pool", allocation_identity = "fixture" },
    gpu_selector                 = "oke-llm/allocation=fixture", gpu_shape = "BM.GPU4.8", node_count = 1, gpu_count_per_host = 8,
    transport                    = { requires_rdma = false }, required_components = ["lws", "prometheus"], monitoring_enabled = true,
    model_onboarding_pipeline_id = "trusted-onboarding", model_onboarding_project_id = "platform-project", model_onboarding_revision = "trusted-source-revision"
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
        recipe = { args = ["--tool-call-parser", "qwen3_coder", "--kv-cache-dtype", "fp8", "--dtype", "bfloat16"], env = { VLLM_USE_RUST_FRONTEND = "1" } }
      }
    }
  }
}
run "apply_onboards_deploys_then_validates" {
  command = apply
  assert {
    condition = (
      oci_devops_deployment.onboarding.deploy_pipeline_id == "trusted-onboarding" &&
      oci_devops_deployment.workload.deploy_pipeline_id == module.delivery.component_pipeline_ids.workload &&
      oci_devops_deployment.validation.deploy_pipeline_id == oci_devops_deploy_pipeline.operation["validate"].id &&
      output.model_delivery.automatically_started && !output.model_delivery.automatic_execution.benchmark_automatically_started &&
      alltrue([for execution in [oci_devops_deployment.onboarding, oci_devops_deployment.workload, oci_devops_deployment.validation] : execution.state == "SUCCEEDED" && !execution.trigger_new_devops_deployment])
    )
    error_message = "Apply must wait for three native successful executions; benchmark remains manual and no unconditional trigger is allowed."
  }
  assert {
    condition = tomap({ for item in oci_devops_deployment.onboarding.deployment_arguments[0].items : item.name => item.value }) == tomap({
      MODEL_NAMESPACE    = output.namespace, MODEL_PROJECT_ID = "project", MODEL_GPU_POOL_ID = "gpu-pool",
      MODEL_PIPELINE_IDS = join(",", sort(output.all_pipeline_ids)), MODEL_ACCESS_OPERATION = "grant"
    })
    error_message = "Trusted onboarding must receive the exact boundary and complete pipeline set as plain comma-separated IDs."
  }
  assert {
    condition     = output.onboarding_arguments == local.onboarding_arguments && output.model_delivery.onboarding.arguments == local.onboarding_arguments && split(",", local.onboarding_arguments.MODEL_PIPELINE_IDS) == sort(output.all_pipeline_ids)
    error_message = "Automatic and manual onboarding must use identical transport arguments that reconstruct the exact sorted pipeline IDs."
  }
  assert {
    condition     = local.config.platform.node_count == 1 && local.config.serving.recipe.args == var.model.selection.serving_configuration.recipe.args && local.config.serving.recipe.env == merge(var.model.selection.serving_configuration.recipe.env, { VLLM_USE_RUST_FRONTEND = "0" }) && local.defaults.VLLM_USE_RUST_FRONTEND == "0"
    error_message = "The stable runtime contract retains complete argv and non-frontend env, records the Python default and computes configured host demand independently from live inventory."
  }
}
run "capacity_and_inventory_refresh_do_not_reexecute" {
  command = plan
  variables {
    platform = merge(var.platform, {
      node_count        = 7, generation = "new-observation", addon_inventory = { scanned_at = "later", driver = "new-summary" },
      retained_gpu_pool = { size = 7, state = "ACTIVE" }, components = { prometheus = { generation = "live-new-generation" } }
    })
    model = merge(var.model, {
      publication_time = "later", capacity = [{ available = 4 }],
      profile          = merge(var.model.profile, { source = { fetched_at = "later" }, diagnostic = "new" }),
      selection        = merge(var.model.selection, { capacity = { available_count = 4, scanned_at = "later" } })
    })
  }
  assert {
    condition     = local.model_execution_revision == run.apply_onboards_deploys_then_validates.model_delivery.automatic_execution.revision && module.delivery.generations.workload == run.apply_onboards_deploys_then_validates.model_delivery.generation
    error_message = "Refreshing capacity, add-ons, trusted controller observations or retained pool size must not rerun an unchanged workload."
  }
}
run "benchmark_backend_is_manual_only" {
  command = plan
  variables {
    benchmark_backend = "openai"
    benchmark_mode = "full"
  }
  assert {
    condition     = local.model_execution_revision == run.apply_onboards_deploys_then_validates.model_delivery.automatic_execution.revision
    error_message = "Changing a manual benchmark client adapter must not redeploy the model."
  }
}
run "effective_configuration_reexecutes" {
  command = apply
  variables { overrides = { context_length = 8192 } }
  assert {
    condition     = local.model_execution_revision != run.apply_onboards_deploys_then_validates.model_delivery.automatic_execution.revision && module.delivery.generations.workload != run.apply_onboards_deploys_then_validates.model_delivery.generation
    error_message = "A meaningful context/geometry/model configuration change must execute corrected pipelines with the new generation."
  }
}
run "frontend_opt_in_reexecutes_with_matching_native_arguments" {
  command = apply
  variables { api_frontend = "rust" }
  assert {
    condition = local.model_execution_revision != run.apply_onboards_deploys_then_validates.model_delivery.automatic_execution.revision && local.config.serving.recipe.env.VLLM_USE_RUST_FRONTEND == "1" && alltrue([
      for execution in [oci_devops_deployment.workload, oci_devops_deployment.validation] : anytrue([for item in execution.deployment_arguments[0].items : item.name == "VLLM_USE_RUST_FRONTEND" && item.value == "1"])
    ])
    error_message = "Frontend selection must be a meaningful revision, and native deploy/validation must receive its exact effective value."
  }
}
run "main_ref_reexecutes_with_matching_native_arguments" {
  command = apply
  variables { overrides = { model_revision = "main" } }
  assert {
    condition = local.model_execution_revision != run.apply_onboards_deploys_then_validates.model_delivery.automatic_execution.revision && local.defaults.MODEL_REVISION == "main" && alltrue([
      for execution in [oci_devops_deployment.workload, oci_devops_deployment.validation] : anytrue([for item in execution.deployment_arguments[0].items : item.name == "MODEL_REVISION" && item.value == "main"])
    ])
    error_message = "The explicit mutable main ref must change the deployment revision and reach both native deploy and validation arguments without an image patch."
  }
}
run "changed_trusted_source_reonboards" {
  command = apply
  variables { platform = merge(var.platform, { model_onboarding_revision = "updated-trusted-source" }) }
  assert {
    condition     = local.model_execution_revision != run.apply_onboards_deploys_then_validates.model_delivery.automatic_execution.revision
    error_message = "A corrected trusted onboarding definition must be executed before the workload again."
  }
}
run "pool_required_before_execution" {
  command = plan
  variables { platform = merge(var.platform, { allocation = { gpu_pool_id = null } }) }
  expect_failures = [oci_devops_deployment.onboarding]
}
run "trusted_onboarding_required_before_execution" {
  command = plan
  variables { platform = merge(var.platform, { model_onboarding_pipeline_id = null }) }
  expect_failures = [oci_devops_deployment.onboarding]
}
run "onboarding_failure_fails_apply" {
  command = apply
  variables { overrides = { context_length = 4100 } }
  override_resource {
    target = oci_devops_deployment.onboarding
    values = { state = "FAILED" }
  }
  expect_failures = [oci_devops_deployment.onboarding]
}
run "workload_failure_fails_apply" {
  command = apply
  variables { overrides = { context_length = 4101 } }
  override_resource {
    target = oci_devops_deployment.workload
    values = { state = "FAILED" }
  }
  expect_failures = [oci_devops_deployment.workload]
}
run "validation_failure_fails_apply" {
  command = apply
  variables { overrides = { context_length = 4102 } }
  override_resource {
    target = oci_devops_deployment.validation
    values = { state = "FAILED" }
  }
  expect_failures = [oci_devops_deployment.validation]
}
