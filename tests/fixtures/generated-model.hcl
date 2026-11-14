# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Copied into an extracted, actually published model ZIP by its package checker.
mock_provider "oci" {
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
    binding_mode = "runtime", platform_name = "llm-platform", cluster_id = "cluster", cluster_compartment_id = "cluster-compartment",
    cluster_type = "ENHANCED_CLUSTER", kubernetes_version = "v1.34.1", vcn_id = "vcn", runner_subnet_id = "runner", runner_nsg_ids = [],
    cpu_shapes = ["VM.Standard.E4.Flex"], gpu_pool_compartment_id = "cluster-compartment", gpu_selector = "oke-llm/allocation=llm-platform",
    gpu_shape = "BM.GPU.H100.8", gpu_count_per_host = 8, node_count = 1, expected_node_count = 1, availability_domain = "AD-1",
    allocation = { gpu_pool_id = null, allocation_identity = null, compute_cluster_id = null }, metadata_ready = true, issues = [],
    free_gpu_headroom = "unknown_other_namespace_requests_not_visible"
  } }
}
run "rendered_cluster_only_stack_owns_independent_model_metadata" {
  command = apply
  assert {
    condition = length(module.project) == 1 && output.model_project.project_id == module.project[0].resources.project_id && output.model_delivery.project_id == output.model_project.project_id && output.model_project.project_id != null && output.model_project.script_repository_id != output.model_project.result_repository_id
    error_message = "The actual configured ZIP must create its own model project/environment/repositories rather than require another stack's project IDs."
  }
  assert {
    condition = local.platform.allocation.gpu_pool_id == null && output.model_delivery.binding_mode == "runtime" && !output.model_delivery.automatically_started && length(module.model[0].all_pipeline_ids) == 4 && output.onboarding_arguments.MODEL_PROJECT_ID == output.model_project.project_id && output.onboarding_arguments.MODEL_GPU_POOL_ID == "runtime" && module.model_storage[0].storage.pipeline_id == null
    error_message = "Cluster-only metadata creation must work before GPU allocation, keep staging opt-in, and expose the exact independent-project onboarding boundary."
  }
}
run "cluster_only_autoscaling_derives_standard_metrics_endpoint" {
  command = plan
  variables {
    autoscaling_enabled = true
    min_replicas        = 1
    max_replicas        = 2
    prometheus_url      = ""
  }
  assert {
    condition = var.prometheus_url == "" && local.platform.allocation.gpu_pool_id == null && contains(local.required_components, "prometheus") && contains(local.required_components, "keda") && module.model[0].model_delivery.defaults.PROMETHEUS_URL == "http://llm-monitoring-kube-prom-prometheus.monitoring.svc.cluster.local:9090"
    error_message = "An autoscaling recommendation must not require a manually supplied Prometheus URL or completed infrastructure Apply to create model pipelines."
  }
}
