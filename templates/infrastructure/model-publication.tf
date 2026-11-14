# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  publication_context = try(local.selected_specification.publication, null)
  selected_model_spec = try(local.selected_specification.model_spec, null)
  modules_dir         = fileexists("${path.module}/modules/llm-deployment/model-delivery/main.tf") ? "${path.module}/modules" : "${path.module}/../../modules"
  model_template_dir  = fileexists("${path.module}/templates/llm-deployment/main.tf") ? "${path.module}/templates/llm-deployment" : "${path.module}/../llm-deployment"
  model_platform_binding = {
    schema_version               = "1.0", platform_name = var.platform_name, generation = module.bootstrap.platform.generation,
    region                       = var.region, cluster_id = var.cluster_id, cluster_compartment_id = module.target.target.cluster_compartment_id,
    kubernetes_version           = module.target.target.kubernetes_version, cluster_authorization = "namespace_rbac",
    compartment_id               = local.compartment_id, project_id = module.bootstrap.platform.project_id,
    deploy_environment_id        = module.bootstrap.platform.deploy_environment_id,
    script_repository_id         = module.bootstrap.platform.script_repository_id, result_repository_id = module.bootstrap.platform.result_repository_id,
    runner_subnet_id             = module.target.target.devops_subnet_id, runner_nsg_ids = module.target.target.devops_nsg_ids,
    allocation                   = module.bootstrap.platform.allocation, gpu_selector = module.bootstrap.platform.gpu_selector,
    gpu_shape                    = var.gpu_shape, node_count = var.node_count, gpu_count_per_host = try(local.gpu.gpus, 0),
    gpu_memory_bytes_per_device  = try(local.gpu.memory_bytes_per_gpu, null), gpu_cpu_architecture = try(local.gpu.cpu_architecture, "amd64"),
    gpu_boot_volume_gib          = var.boot_volume_gib, storage_budget = try(local.selected_specification.storage_budget, null),
    gpu_allocation_enabled       = !var.skip_gpu_allocation,
    transport                    = { requires_rdma = local.requires_rdma, rdma_resource_name = var.rdma_resource_name, mode = local.requires_rdma ? "rdma" : "ethernet" },
    cpu_placement                = "existing_cluster_cpu_pools", cpu_shape_names = try(module.target.target.cpu_shapes, []),
    cpu_node_selector            = try(length(module.target.target.cpu_shapes) > 0 ? { "node.kubernetes.io/instance-type" = module.target.target.cpu_shapes[0] } : {}, {}),
    component_generations        = module.bootstrap.platform.component_generations, required_components = module.bootstrap.platform.required_components,
    components                   = module.bootstrap.platform.components, prometheus_url = module.bootstrap.platform.prometheus_url,
    monitoring_enabled           = module.bootstrap.platform.monitoring_enabled, autoscaling_enabled = module.bootstrap.platform.autoscaling_enabled,
    model_onboarding_pipeline_id = module.bootstrap.platform.model_onboarding_pipeline_id,
    model_onboarding             = module.bootstrap.platform.model_onboarding,
    model_storage                = module.model_storage.storage,
    recommendation_changes       = local.recommendation_changes,
    runtime_validation           = "not_run; CPU debug bindings may create pipelines but cannot deploy a GPU runtime"
  }
}
provider "oci" {
  alias  = "publication"
  region = try(coalesce(local.publication_context.region, var.region), var.region)
}
module "model_publication" {
  providers        = { oci = oci.publication }
  source           = "../../modules/discovery/model-publisher"
  model_spec       = local.selected_model_spec
  platform_binding = local.model_platform_binding
  publication      = local.publication_context
  template_dir     = local.model_template_dir
  modules_dir      = local.modules_dir
}
output "model_deployment" {
  description = "Configured model-only ZIP using the existing platform. Create pipelines and run trusted onboarding; no model starts automatically."
  value       = module.model_publication.deployment
}
output "model_platform_binding" {
  description = "Small credential-free binding consumed by the generated model stack; does not assert serving readiness."
  value       = local.model_platform_binding
}
output "model_launch_url" {
  description = "Create the configured model-only RMS stack in this platform's region. Does not execute any pipeline."
  value       = try(module.model_publication.deployment.launch_url, null)
}
