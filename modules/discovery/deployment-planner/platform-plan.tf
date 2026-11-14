# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  # Runtime arguments are evidence, not permission to execute installation or
  # companion shell commands. Only explicit selections imply capabilities.
  platform_options = { for option in concat(local.raw_candidates, local.raw_suggestions) : option.id => {
    option  = option
    recipe  = try(option.serving_configuration.recipe, var.serving_resolution.recipe, {})
    backend = try(option.serving_configuration.engine.multi_node_backend, option.engine.multi_node_backend, "mp")
  } }
  platform_capabilities = { for id, p in local.platform_options : id => {
    pd_selected  = try(p.recipe.api.selection.pd != null, false)
    companions   = try(p.recipe.companions, [])
    dependencies = try(p.recipe.dependencies, p.recipe.install_requirements, [])
    selection    = try(p.recipe.api.selection, {})
    unclassified_features = setsubtract(toset(try(p.recipe.api.selection.features, p.recipe.selected_features, [])), toset([
      "tool_calling", "reasoning", "encoder_parallel", "text_only", "spec_decoding", "long_context"
    ]))
  } }
  platform_plans = { for id, p in local.platform_options : id => {
    schema_version    = "1.0"
    status            = "requires_validation"
    auto_deploy_ready = false
    workload = {
      context_length                  = try(local.profile.memory.assumptions.context_length, null)
      concurrency_per_replica         = try(local.profile.memory.assumptions.concurrency, null)
      estimated_aggregate_concurrency = try(local.profile.memory.assumptions.concurrency * p.option.replicas, null)
      status                          = "repeated_per_replica_memory_budget; aggregate concurrency is a sizing assumption, not measured throughput"
    }
    monitoring = { enabled = var.monitoring_enabled, source = "install_or_reuse", prometheus_required = var.monitoring_enabled || var.autoscaling_enabled }
    autoscaling = {
      enabled                                 = var.autoscaling_enabled
      metrics_source                          = "prometheus"
      target_kind                             = local.platform_capabilities[id].pd_selected ? "DisaggregatedSetRoleScaler" : p.option.pipeline_parallel_size > 1 ? "LeaderWorkerSet" : "Deployment"
      min_replicas                            = var.replicas
      max_replicas                            = p.option.replicas
      initial_replicas                        = var.autoscaling_enabled ? var.replicas : p.option.replicas
      capacity_scope                          = "complete_replicas_inside_the_retained_allocation"
      additional_capacity_required_for_growth = var.autoscaling_enabled && p.option.replicas <= var.replicas
      status                                  = var.autoscaling_enabled ? "requires_workload_metrics_validation" : "disabled"
    }
    topology = {
      strategy                   = local.platform_capabilities[id].pd_selected ? "disaggregated_requires_adapter" : p.option.pipeline_parallel_size > 1 ? "multi_node_tp_pp" : "single_node_tp"
      backend                    = p.backend
      nodes_per_replica          = p.option.pipeline_parallel_size
      replicas_per_node          = p.option.replicas_per_node
      node_count                 = p.option.node_count
      replicas                   = p.option.replicas
      requested_minimum_replicas = var.replicas
      gpus_per_replica           = p.option.tensor_parallel_size * p.option.pipeline_parallel_size
      unused_gpus_per_node       = p.option.gpus_per_node - p.option.tensor_parallel_size * p.option.replicas_per_node
      network                    = p.option.requires_rdma ? "rdma" : p.option.pipeline_parallel_size > 1 ? "ethernet" : "intra_node"
      rdma_required              = p.option.requires_rdma
      placement_status           = "analytical_packing_requires_workload_validation"
      placement_contract         = p.option.pipeline_parallel_size == 1 ? "Each complete replica must request its own distinct GPU resources; enforce the computed replicas-per-host placement without assigning the same GPU to two replicas." : "Each replica spans one complete PP host group; groups must be co-scheduled and use distinct GPU resources. Spare GPU packing across PP groups is not inferred."
    }
    routing = {
      required       = p.option.replicas > 1 || local.platform_capabilities[id].pd_selected
      implementation = null
      status         = p.option.replicas > 1 || local.platform_capabilities[id].pd_selected ? "requires_validation" : "not_required"
      reason         = local.platform_capabilities[id].pd_selected ? "Separate prefill/decode roles require a compatible coordinating router and connector." : p.option.replicas > 1 ? "Multiple fixed replicas need an explicit endpoint routing policy; replica packing does not enable autoscaling." : "One model endpoint needs no additional inference routing controller."
      contract       = ["Select an implemented adapter before model deployment.", "Route only to ready model endpoints and preserve streaming, cancellation and the selected API paths.", "Validate cache affinity and KV transfer when selected; routing does not provide durable conversation history."]
    }
    components = {
      lws = {
        required                 = (p.option.pipeline_parallel_size > 1 && p.backend != "ray") || local.platform_capabilities[id].pd_selected
        enable_disaggregated_set = local.platform_capabilities[id].pd_selected
        depends_on               = []
      }
      prometheus       = { required = var.monitoring_enabled || var.autoscaling_enabled, depends_on = [] }
      keda             = { required = var.autoscaling_enabled, depends_on = [] }
      kuberay          = { required = p.option.pipeline_parallel_size > 1 && p.backend == "ray", depends_on = [] }
      kueue            = { required = false, depends_on = [] }
      gpu_telemetry    = { required = var.monitoring_enabled, reuse_oke_addon = true, depends_on = [] }
      network_operator = { required = p.option.requires_rdma, reuse_oke_addon = true, depends_on = [] }
    }
    cpu_budget = {
      status               = "requires_cluster_inventory_and_chart_requests"
      additional_cpu_nodes = 0
      items = compact([
        "Existing CPU pools host enabled controllers; validate allocatable resources before installation.",
        var.monitoring_enabled || var.autoscaling_enabled ? "Prometheus scrape and retention load require chart requests and cluster headroom assessment." : "",
        var.autoscaling_enabled ? "KEDA operator and metrics API require CPU-pool headroom." : "",
        p.option.replicas > 1 || local.platform_capabilities[id].pd_selected ? "The selected routing adapter needs explicit CPU and memory requests." : "",
        length(local.platform_capabilities[id].companions) > 0 ? "Recipe companions require explicit placement and CPU/host-memory budgets; do not copy example cache sizes." : ""
      ])
    }
    storage_budget = {
      status              = "requires_storage_policy_and_capacity_validation"
      model_cache_bytes   = try(local.profile.weights.tensor_data_bytes, local.profile.memory.weight_bytes, null)
      kv_offload_bytes    = null
      prometheus_bytes    = null
      allocation_contract = "Model-cache bytes describe checkpoint payload only, not a PVC size. Model staging, temporary files, retention, storage class and any selected offload tier require separate budgets."
    }
    recipe_evidence = {
      selection    = local.platform_capabilities[id].selection
      companions   = local.platform_capabilities[id].companions
      dependencies = local.platform_capabilities[id].dependencies
    }
    diagnostics = concat(
      [{ code = "runtime_not_validated", status = "requires_validation", message = "GPU placement, per-rank memory, node drivers/network and serving behavior have not been validated by this plan." }],
      var.autoscaling_enabled && p.option.replicas <= var.replicas ? [{ code = "autoscaling_has_no_growth_headroom", status = "requires_configuration", message = "The retained allocation has no complete replica slot above the requested minimum. Scaling growth needs a different layout or larger allocation with a new quantity-specific capacity check." }] : [],
      p.option.replicas > 1 || local.platform_capabilities[id].pd_selected ? [{ code = "routing_adapter_required", status = "requires_validation", message = "A compatible routing adapter must be selected and validated before model deployment; no complex routing stack is silently enabled." }] : [],
      length(local.platform_capabilities[id].companions) > 0 ? [{ code = "recipe_companion_adapter_required", status = "requires_validation", message = "Complete recipe companion commands are preserved as evidence. Kubernetes resources, placement, readiness and resource limits are not inferred or executed." }] : [],
      length(local.platform_capabilities[id].dependencies) > 0 ? [{ code = "recipe_dependencies_unverified", status = "requires_validation", message = "Verify recipe dependencies exist in the selected immutable image; dependency installation commands are not executed." }] : [],
      [for feature in sort(tolist(local.platform_capabilities[id].unclassified_features)) : { code = "feature_integration_unclassified", status = "requires_validation", message = "Selected feature ${feature} is retained in recipe evidence; shared-controller or companion requirements are not classified." }],
      local.platform_capabilities[id].pd_selected ? [{ code = "disaggregation_adapter_required", status = "requires_validation", message = "Selected P/D mode needs role-specific resources, a compatible KV-transfer connector, routing and network validation; LWS CRDs alone are insufficient." }] : []
    )
  } }
  candidates           = [for option in local.raw_candidates : merge(option, { platform_plan = local.platform_plans[option.id] })]
  suggestions          = [for option in local.raw_suggestions : merge(option, { platform_plan = local.platform_plans[option.id] })]
  candidate_rank_index = { for option in local.candidates : format("%08d-%04d-%03d-%s", option.node_count * option.gpus_per_node, option.node_count, option.tensor_parallel_size, option.id) => option }
  ranked_candidates    = [for key in sort(keys(local.candidate_rank_index)) : local.candidate_rank_index[key]]
}
