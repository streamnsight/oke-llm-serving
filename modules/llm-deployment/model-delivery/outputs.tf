# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
output "namespace" { value = local.namespace }
output "all_pipeline_ids" { value = local.all_pipeline_ids }
output "onboarding_arguments" { value = local.onboarding_arguments }
output "model_delivery" {
  value = {
    schema_version        = "1.0", name = local.name, namespace = local.namespace, identity = local.identity,
    project_id            = var.platform.project_id, cluster_id = var.platform.cluster_id, generation = module.delivery.generations.workload,
    deploy_pipeline_id    = module.delivery.component_pipeline_ids.workload,
    validate_pipeline_id  = oci_devops_deploy_pipeline.operation["validate"].id,
    benchmark_pipeline_id = oci_devops_deploy_pipeline.operation["benchmark"].id,
    undeploy_pipeline_id  = module.delivery.undeploy_pipeline_ids.workload,
    onboarding            = { pipeline_name = "${var.platform.platform_name}-model-onboarding", pipeline_id = try(var.platform.model_onboarding_pipeline_id, null), arguments = local.onboarding_arguments },
    binding_mode          = try(var.platform.binding_mode, "frozen"), expected_platform_name = var.platform.platform_name,
    gpu_readiness         = "runtime_validation_required; no GPU pool is created or modified by this model stack",
    free_gpu_headroom     = "unknown_other_namespace_requests_not_visible",
    chart_repositories    = module.delivery.chart_repositories,
    endpoint              = local.router_enabled ? "http://${local.name}-router-service.${local.namespace}.svc:80" : "http://${local.name}.${local.namespace}.svc:8000",
    port_forward          = "kubectl -n ${local.namespace} port-forward service/${local.router_enabled ? "${local.name}-router-service" : local.name} 8000:${local.router_enabled ? 80 : 8000}",
    routing               = local.routing_mode,
    cache_capabilities    = module.cache_capabilities.assessment,
    lmcache               = merge(local.lmcache, { enabled = local.lmcache_enabled, validation = "runtime_store_retrieve_required" }),
    defaults              = local.defaults, workspace_gib_per_pod = local.workspace_gib,
    storage               = var.storage.mode, automatically_started = true,
    automatic_execution = {
      revision                        = local.model_execution_revision,
      onboarding                      = { id = oci_devops_deployment.onboarding.id, state = oci_devops_deployment.onboarding.state },
      deployment                      = { id = oci_devops_deployment.workload.id, state = oci_devops_deployment.workload.state },
      validation                      = { id = oci_devops_deployment.validation.id, state = oci_devops_deployment.validation.state },
      benchmark_automatically_started = false
    },
    runtime_validation                 = "Apply waits for trusted onboarding, model deployment and independent validation. An unchanged Apply reuses these completed executions; inference is checked only when its probe is enabled.",
    responses_conversation_persistence = false,
    teardown                           = "Run the guarded undeploy pipeline before destroying pipeline definitions. Namespace, CRDs, PVCs, platform controllers and GPU allocation are retained."
  }
}
