# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12" } }
}
locals {
  model           = try(jsondecode(file("${path.module}/inputs/model-spec.json")), null)
  configured      = local.model != null
  compartment_id  = coalesce(var.compartment_id, var.compartment_ocid, var.tenancy_ocid)
  expected_region = try(local.model.selection.region, null)
  model_name      = coalesce(var.model_name, "model-${substr(sha256(try(local.model.model.repository, "unconfigured/model")), 0, 10)}")
  namespace_base  = coalesce(var.namespace, "${try(module.target[0].target.platform_name, coalesce(var.platform_name, "llm-platform"))}-model-${substr(sha256(local.model_name), 0, 12)}")
  project_name    = "${local.model_name}-${substr(sha256("${var.cluster_id}/${local.namespace_base}"), 0, 8)}"
  # Legacy projects keep their retained namespace. New stack instances receive
  # a separate default namespace; an explicit namespace remains an expert choice.
  model_namespace = coalesce(var.namespace, try(module.project[0].resources.instance_key, null) == null ? local.namespace_base :
  "${try(module.target[0].target.platform_name, coalesce(var.platform_name, "llm-platform"))}-model-${substr(sha256("${local.model_name}/${module.project[0].resources.instance_key}"), 0, 12)}")
  assessed_components = try(local.model.selection.platform_plan.components, {})
  hosts_per_replica   = coalesce(var.hosts_per_replica, var.pipeline_parallel_size, try(local.model.selection.hosts_per_replica, null), try(local.model.selection.pipeline_parallel_size, null), 1)
  monitoring_required = var.monitoring_enabled || var.autoscaling_enabled
  component_requirements = merge(local.assessed_components, {
    prometheus    = merge(try(local.assessed_components.prometheus, {}), { required = local.monitoring_required }),
    keda          = merge(try(local.assessed_components.keda, {}), { required = var.autoscaling_enabled }),
    gpu_telemetry = merge(try(local.assessed_components.gpu_telemetry, {}), { required = var.monitoring_enabled })
  })
  required_components = sort(distinct(concat(
    [for name, config in local.component_requirements : name if try(config.required, false) && !contains(["lws", "prometheus", "keda", "gpu_telemetry", "network_operator"], name)],
    local.hosts_per_replica > 1 ? ["lws"] : [], local.monitoring_required ? ["prometheus"] : [], var.autoscaling_enabled ? ["keda"] : []
  )))
  prometheus_url = coalesce(var.prometheus_url, "http://llm-monitoring-kube-prom-prometheus.monitoring.svc.cluster.local:9090")
  expected = {
    gpu_shape           = try(local.model.selection.gpu_shape, "")
    availability_domain = try(local.model.selection.availability_domain, "")
    node_count          = try(local.model.selection.node_count, 0)
    gpu_count_per_host  = try(local.model.selection.gpus_per_node, local.model.selection.gpu_count_per_host, 0)
  }
}
provider "oci" { region = try(coalesce(var.region, local.expected_region), null) }
data "oci_identity_tenancy" "target" { tenancy_id = var.tenancy_ocid }
data "oci_identity_regions" "available" {}
provider "oci" {
  alias  = "home"
  region = one([for region in data.oci_identity_regions.available.regions : region.name if region.key == data.oci_identity_tenancy.target.home_region_key])
}
module "target" {
  count                   = local.configured ? 1 : 0
  source                  = "../../modules/llm-deployment/model-target"
  cluster_id              = var.cluster_id
  compartment_id          = local.compartment_id
  gpu_pool_id             = try(trimspace(var.gpu_pool_id) != "" ? trimspace(var.gpu_pool_id) : null, null)
  gpu_pool_compartment_id = try(trimspace(var.gpu_pool_compartment_id) != "" ? trimspace(var.gpu_pool_compartment_id) : null, null)
  platform_name           = var.platform_name
  runner_subnet_id        = try(trimspace(var.runner_subnet_id) != "" ? trimspace(var.runner_subnet_id) : null, null)
  runner_nsg_ids          = var.runner_nsg_ids
  expected                = local.expected
}
resource "terraform_data" "binding" {
  input = { configured = local.configured }
  lifecycle {
    precondition {
      condition     = local.configured
      error_message = "Use a configured model ZIP published by discovery: inputs/model-spec.json is required. Apply the retained GPU infrastructure and shared components before the model stack."
    }
    precondition {
      condition     = !local.configured || var.region == null ? true : var.region == local.expected_region
      error_message = "This model ZIP assesses another region. Open its generated regional RMS URL and select a cluster in that region."
    }
    precondition {
      condition     = try(module.target[0].target.metadata_ready, !local.configured)
      error_message = "Model target metadata failed: ${join("; ", try(module.target[0].target.issues, []))}"
    }
  }
}
module "project" {
  count          = local.configured ? 1 : 0
  source         = "../../modules/llm-deployment/model-project"
  name           = local.project_name
  compartment_id = local.compartment_id
  target         = module.target[0].target
  depends_on     = [terraform_data.binding]
}
locals {
  platform = local.configured ? merge(module.target[0].target, module.project[0].resources, {
    schema_version      = "3.0", binding_mode = "runtime", region = coalesce(var.region, local.expected_region),
    generation          = "resolve_current_platform_at_execution", cluster_authorization = "namespace_rbac",
    required_components = local.required_components, component_requirements = local.component_requirements,
    addon_requirements  = { for name, config in local.component_requirements : name => config if contains(["gpu_telemetry", "network_operator"], name) && try(config.required, false) },
    components          = {}, monitoring_enabled = local.monitoring_required,
    transport           = { requires_rdma = try(local.model.selection.requires_rdma, local.model.selection.platform_plan.topology.rdma_required, false), rdma_resource_name = var.rdma_resource_name },
    model_storage       = module.model_storage[0].storage,
    readiness           = "Apply resolves trusted onboarding, deploys the model, and validates runtime readiness; benchmarking remains manual"
  }) : null
}
module "model" {
  count          = local.configured ? 1 : 0
  source         = "../../modules/llm-deployment/model-delivery"
  providers      = { oci = oci, oci.home = oci.home }
  tenancy_ocid   = var.tenancy_ocid
  compartment_id = local.compartment_id
  platform       = local.platform
  model          = local.model
  name           = local.model_name
  namespace      = local.model_namespace
  overrides = {
    model_id             = var.model_id, model_revision = var.model_revision, serving_image = var.serving_image,
    tensor_parallel_size = var.tensor_parallel_size, pipeline_parallel_size = var.pipeline_parallel_size,
    hosts_per_replica    = var.hosts_per_replica, gpus_per_pod = var.gpus_per_pod, replicas = var.replicas,
    context_length       = var.context_length, concurrency = var.concurrency
  }
  storage                  = { mode = var.storage_mode, pvc_name = var.model_pvc_name, model_path = var.model_path, workspace_gib = var.workspace_gib }
  hf_token_secret          = var.hf_token_secret
  api_frontend             = var.api_frontend
  router_enabled           = var.router_enabled
  routing_mode             = var.routing_mode
  lmcache_mode             = var.lmcache_mode
  lmcache_cpu_memory_gb    = var.lmcache_cpu_memory_gb
  lmcache_chunk_size       = var.lmcache_chunk_size
  lmcache_mamba_cache_mode = var.lmcache_mamba_cache_mode
  inference_probe          = var.inference_probe
  benchmark_backend        = var.benchmark_backend
  benchmark_mode           = var.benchmark_mode
  autoscaling              = { enabled = var.autoscaling_enabled, min_replicas = var.min_replicas, max_replicas = var.max_replicas, prometheus_url = local.prometheus_url, target_inflight = var.target_inflight }
  depends_on               = [terraform_data.binding]
}
output "model_delivery" { value = try(module.model[0].model_delivery, null) }
output "onboarding_arguments" { value = try(module.model[0].onboarding_arguments, null) }
output "model_project" { value = try(module.project[0].resources, null) }
output "target_preview" { value = try(module.target[0].target, null) }
