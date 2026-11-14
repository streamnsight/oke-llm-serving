# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variables {
  engines               = [{ id = "fixture", framework = "vllm", version = "0.33.0", image = "fixture", platform = "linux/amd64", architectures = ["LlamaForCausalLM"], gpu_compute_capabilities = [80], multi_node_backend = "mp" }]
  max_nodes_per_replica = 2
  profile = {
    model                = { repository = "org/model", chat_template_available = true, pipeline_tag = "text-generation", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
    architecture         = { architectures = ["LlamaForCausalLM"], attention = { layers = 4, heads = 8, kv_heads = 2, hidden_size = 64, vocab_size = 100 } }
    weights              = { elements_by_dtype = { BF16 = 100 } }
    memory               = { status = "estimated", weight_bytes = 1000000, kv_bytes = 10000, runtime_allowance_bytes = 1000, assumptions = { safety_margin_fraction = 0.2 } }
    serving_requirements = { version_hints = [] }
  }
  regions = [{
    inventory = {
      region               = "region-one"
      availability_domains = [{ name = "AD-1", shapes = [{ shape = "BM.GPU4.8", gpus = 8, rdma_ports = 0, quota_names = ["gpu-count"] }] }]
      limits               = [{ name = "gpu-count", description = "GPUs for instances", tenancy_limit = 16, scope_type = "AD", availability_domain = "AD-1", resource_availability = { available = 16, status = "observed" } }]
    }
    capacity = { region = "region-one", availability_domains = [{ name = "AD-1", assessment = { observed_at = "fixture", shapes = [{ shape = "BM.GPU4.8", available_instances = 2, availability_status = "AVAILABLE" }] } }] }
  }]
}

run "fixed_replicas_fill_spare_gpu_slots_without_autoscaling" {
  command = plan
  assert {
    condition     = alltrue([for c in output.assessment.candidates : c.node_count == 1 && c.replicas == 2 && c.replicas_per_node == 2 && c.requested_minimum_replicas == 1 && c.platform_plan.topology.unused_gpus_per_node == 0 if c.tensor_parallel_size == 4 && c.pipeline_parallel_size == 1]) && length([for c in output.assessment.candidates : c if c.tensor_parallel_size == 4 && c.pipeline_parallel_size == 1]) == 1
    error_message = "An eight-GPU host with TP4 must run two complete fixed replicas using one allocated host."
  }
  assert {
    condition     = alltrue([for c in output.assessment.candidates : !c.platform_plan.autoscaling.enabled && c.platform_plan.components.prometheus.required && c.platform_plan.routing.required && c.platform_plan.routing.implementation == null && c.platform_plan.topology.placement_status == "analytical_packing_requires_workload_validation" if c.tensor_parallel_size == 4 && c.pipeline_parallel_size == 1])
    error_message = "Monitoring defaults on, autoscaling stays off, and additional fixed replicas require an explicit routing and distinct-GPU placement contract."
  }
}

run "minimum_replicas_round_up_inside_the_hosts_the_minimum_needs" {
  command = plan
  variables { replicas = 3 }
  assert {
    condition     = alltrue([for c in output.assessment.candidates : c.node_count == 2 && c.replicas == 4 && c.entitlement == "confirmed_for_quantity" if c.tensor_parallel_size == 4 && c.pipeline_parallel_size == 1]) && length([for c in output.assessment.candidates : c if c.tensor_parallel_size == 4 && c.pipeline_parallel_size == 1]) == 1 && output.assessment.shape_observations[0].eligible_at_scan
    error_message = "Three requested TP4 replicas need two eight-GPU hosts and may fill their fourth replica slot."
  }
}

run "packing_does_not_create_hosts_beyond_confirmed_capacity" {
  command = plan
  variables { replicas = 5 }
  assert {
    condition     = length([for c in output.assessment.candidates : c if c.tensor_parallel_size == 4 && c.pipeline_parallel_size == 1]) == 0
    error_message = "Five TP4 replicas need three full hosts, which the two-host capacity observation cannot confirm."
  }
}

run "packing_requires_entitlement_for_whole_hosts" {
  command = plan
  variables {
    replicas = 3
    regions  = [{ inventory = { region = "region-one", availability_domains = [{ name = "AD-1", shapes = [{ shape = "BM.GPU4.8", gpus = 8, rdma_ports = 0, quota_names = ["gpu-count"] }] }], limits = [{ name = "gpu-count", description = "GPUs for instances", tenancy_limit = 16, scope_type = "AD", availability_domain = "AD-1", resource_availability = { available = 8, status = "observed" } }] }, capacity = { region = "region-one", availability_domains = [{ name = "AD-1", assessment = { observed_at = "fixture", shapes = [{ shape = "BM.GPU4.8", available_instances = 2, availability_status = "AVAILABLE" }] } }] } }]
  }
  assert {
    condition     = length([for c in output.assessment.candidates : c if c.tensor_parallel_size == 4 && c.pipeline_parallel_size == 1]) == 0
    error_message = "Spare GPU packing must not confuse used model GPUs with the entitlement required for two whole eight-GPU hosts."
  }
}

run "pipeline_parallel_replicas_keep_complete_host_groups" {
  command = plan
  assert {
    condition     = alltrue([for c in output.assessment.candidates : c.node_count == 2 && c.replicas == 1 && c.replicas_per_node == 1 && c.platform_plan.topology.unused_gpus_per_node == 4 && c.platform_plan.components.lws.required && !c.platform_plan.components.lws.enable_disaggregated_set if c.tensor_parallel_size == 4 && c.pipeline_parallel_size == 2]) && length([for c in output.assessment.candidates : c if c.tensor_parallel_size == 4 && c.pipeline_parallel_size == 2]) == 1
    error_message = "A PP2 replica keeps a complete two-host group; do not infer cross-host placement for extra spare-GPU replicas."
  }
}

run "autoscaling_is_opt_in_and_requires_metrics_even_without_monitoring" {
  command = plan
  variables {
    monitoring_enabled  = false
    autoscaling_enabled = true
  }
  assert {
    condition     = alltrue([for c in output.assessment.candidates : c.platform_plan.autoscaling.enabled && !c.platform_plan.monitoring.enabled && c.platform_plan.components.prometheus.required && c.platform_plan.components.keda.required && c.platform_plan.autoscaling.max_replicas == null && c.platform_plan.cpu_budget.additional_cpu_nodes == 0])
    error_message = "KEDA still requires Prometheus metrics when optional monitoring is disabled; unknown scaling bounds and CPU capacity must remain explicit."
  }
}

run "monitoring_and_autoscaling_can_both_be_disabled" {
  command = plan
  variables { monitoring_enabled = false }
  assert {
    condition     = alltrue([for c in output.assessment.candidates : !c.platform_plan.components.prometheus.required && !c.platform_plan.components.keda.required && !c.platform_plan.components.gpu_telemetry.required && !c.platform_plan.components.kueue.required])
    error_message = "Unselected telemetry/autoscaling/admission capabilities must not imply component pipelines."
  }
}
