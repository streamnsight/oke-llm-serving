# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Copied into an extracted, actually published model ZIP by its package checker.
mock_provider "oci" {
  mock_resource "oci_devops_deployment" { defaults = { state = "SUCCEEDED" } }
  mock_data "oci_core_subnet" { defaults = { compartment_id = "network-compartment" } }
  mock_data "oci_objectstorage_namespace" { defaults = { namespace = "fixture" } }
  mock_data "oci_identity_tenancy" { defaults = { home_region_key = "ORD" } }
  mock_data "oci_identity_regions" { defaults = { regions = [{ key = "ORD", name = "us-chicago-1" }] } }
}
mock_provider "oci" { alias = "home" }
variables {
  tenancy_ocid     = "tenancy"
  compartment_ocid = "stack-compartment"
  cluster_id       = "cluster"
}
override_module {
  target = module.target
  outputs = { target = {
    binding_mode                 = "runtime", platform_name = "llm-platform", cluster_id = "cluster", cluster_compartment_id = "cluster-compartment",
    cluster_type                 = "ENHANCED_CLUSTER", kubernetes_version = "v1.34.1", vcn_id = "vcn", runner_subnet_id = "runner", runner_nsg_ids = [],
    cpu_shapes                   = ["VM.Standard.E4.Flex"], gpu_pool_compartment_id = "cluster-compartment", gpu_selector = "oke-llm/allocation=llm-platform",
    gpu_shape                    = "BM.GPU.H100.8", gpu_count_per_host = 8, node_count = 1, expected_node_count = 1, availability_domain = "AD-1",
    allocation                   = { gpu_pool_id = "ocid1.nodepool.oc1.fixture.retained", allocation_identity = "retained-allocation", compute_cluster_id = null }, metadata_ready = true, issues = [],
    model_onboarding_pipeline_id = "ocid1.devopsdeploypipeline.oc1.fixture.onboarding", model_onboarding_project_id = "ocid1.devopsproject.oc1.fixture.platform", model_onboarding_revision = "stable-trusted-onboarding-revision",
    free_gpu_headroom            = "unknown_other_namespace_requests_not_visible"
  } }
}
run "rendered_cluster_only_stack_autoruns_an_independent_model_project" {
  command = apply
  assert {
    condition     = length(module.project) == 1 && output.model_project.project_id == module.project[0].resources.project_id && output.model_delivery.project_id == output.model_project.project_id && output.model_project.project_id != null && output.model_project.script_repository_id != output.model_project.result_repository_id
    error_message = "The actual configured ZIP must create its own model project/environment/repositories rather than require another stack's project IDs."
  }
  assert {
    condition     = local.platform.allocation.gpu_pool_id == "ocid1.nodepool.oc1.fixture.retained" && output.model_delivery.binding_mode == "runtime" && output.model_delivery.automatically_started && length(module.model[0].all_pipeline_ids) == 4 && output.onboarding_arguments.MODEL_PROJECT_ID == output.model_project.project_id && output.onboarding_arguments.MODEL_GPU_POOL_ID == local.platform.allocation.gpu_pool_id && module.model_storage[0].storage.pipeline_id == null
    error_message = "Entering only the cluster must use the inferred existing allocation and trusted onboarding boundary, start model delivery and leave weight staging opt-in."
  }
  assert {
    condition     = output.model_delivery.onboarding.pipeline_id == local.platform.model_onboarding_pipeline_id && output.model_delivery.automatic_execution.onboarding.state == "SUCCEEDED" && output.model_delivery.automatic_execution.deployment.state == "SUCCEEDED" && output.model_delivery.automatic_execution.validation.state == "SUCCEEDED" && !output.model_delivery.automatic_execution.benchmark_automatically_started
    error_message = "The generated model stack must wait for trusted onboarding, deployment and independent validation; benchmarks remain manual."
  }
  assert {
    condition     = var.api_frontend == "python" && output.model_delivery.defaults.VLLM_USE_RUST_FRONTEND == "0"
    error_message = "A generated model stack must default to the Python frontend even when the recipe opts into Rust."
  }
  assert {
    condition     = can(regex("^[a-f0-9]{40}$", output.model_delivery.defaults.MODEL_REVISION))
    error_message = "The generated stack must continue to default to an immutable discovery commit."
  }
}
run "model_deployment_can_select_main_without_rewriting_the_assessed_commit" {
  command = apply
  variables {
    model_revision = "main"
    storage_mode   = "direct_hf"
  }
  assert {
    condition     = output.model_delivery.defaults.MODEL_REVISION == "main" && output.model_delivery.storage == "direct_hf" && can(regex("^[a-f0-9]{40}$", local.model.model.revision)) && output.model_delivery.defaults.SERVING_IMAGE == run.rendered_cluster_only_stack_autoruns_an_independent_model_project.model_delivery.defaults.SERVING_IMAGE && output.model_delivery.automatic_execution.deployment.state == "SUCCEEDED" && output.model_delivery.automatic_execution.validation.state == "SUCCEEDED"
    error_message = "The direct-HF main override must reach model deployment/validation while retaining the assessed commit and exact serving image."
  }
}
run "model_deployment_can_opt_into_rust_frontend" {
  command = plan
  variables { api_frontend = "rust" }
  assert {
    condition     = module.model[0].model_delivery.defaults.VLLM_USE_RUST_FRONTEND == "1"
    error_message = "The advanced root frontend choice must reach the editable deployment pipeline parameter."
  }
}
run "cluster_only_autoscaling_derives_standard_metrics_endpoint" {
  command = plan
  variables {
    monitoring_enabled  = false
    autoscaling_enabled = true
    min_replicas        = 1
    max_replicas        = 2
    prometheus_url      = ""
  }
  assert {
    condition     = var.prometheus_url == "" && local.platform.allocation.gpu_pool_id == "ocid1.nodepool.oc1.fixture.retained" && contains(local.required_components, "prometheus") && contains(local.required_components, "keda") && local.component_requirements.prometheus.required && local.component_requirements.keda.required && !local.component_requirements.gpu_telemetry.required && module.model[0].model_delivery.defaults.PROMETHEUS_URL == "http://llm-monitoring-kube-prom-prometheus.monitoring.svc.cluster.local:9090"
    error_message = "An autoscaling recommendation derives the standard metrics endpoint while reusing the selected existing allocation and shared controllers."
  }
}
run "model_deployment_can_disable_monitoring_and_select_its_own_weight_delivery" {
  command = plan
  variables {
    monitoring_enabled  = false
    autoscaling_enabled = false
    storage_mode        = "existing_pvc"
    model_pvc_name      = "retained-weights"
  }
  assert {
    condition     = !local.platform.monitoring_enabled && !contains(local.required_components, "prometheus") && !contains(local.required_components, "keda") && !local.component_requirements.prometheus.required && !local.component_requirements.keda.required && !contains(keys(local.platform.addon_requirements), "gpu_telemetry") && module.model[0].model_delivery.storage == "existing_pvc" && module.model_storage[0].storage.bucket_name == null
    error_message = "Discovery recommendations must not freeze monitoring requirements or weight delivery; model-stage choices own them and autoscaling remains off."
  }
}
