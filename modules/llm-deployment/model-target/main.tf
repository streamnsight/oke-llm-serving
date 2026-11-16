# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12" } }
}
data "oci_containerengine_cluster" "target" { cluster_id = var.cluster_id }
data "oci_containerengine_node_pool" "selected" {
  count        = local.selected_pool_id == null ? 0 : 1
  node_pool_id = local.selected_pool_id
}
data "oci_containerengine_node_pools" "cluster" {
  compartment_id = data.oci_containerengine_cluster.target.compartment_id
  cluster_id     = var.cluster_id
}
data "oci_containerengine_node_pools" "gpu_scope" {
  count          = var.gpu_pool_compartment_id == null ? 0 : var.gpu_pool_compartment_id == data.oci_containerengine_cluster.target.compartment_id ? 0 : 1
  compartment_id = var.gpu_pool_compartment_id
  cluster_id     = var.cluster_id
}
locals {
  platform_override = try(trimspace(var.platform_name) != "" ? trimspace(var.platform_name) : null, null)
  candidate_scope   = try(data.oci_containerengine_node_pools.gpu_scope[0].node_pools, data.oci_containerengine_node_pools.cluster.node_pools)
  candidate_labels  = { for pool in local.candidate_scope : pool.id => { for label in pool.initial_node_labels : label.key => label.value } }
  compatible_pools = [for pool in local.candidate_scope : pool if pool.node_shape == var.expected.gpu_shape &&
    !contains(["DELETING", "DELETED"], pool.state) &&
    try(coalesce(pool.freeform_tags["oke-llm-allocation"], ""), "") != "" &&
    try(coalesce(local.candidate_labels[pool.id]["oke-llm/allocation"], ""), "") != "" &&
    (local.platform_override == null || try(local.candidate_labels[pool.id]["oke-llm/allocation"] == local.platform_override, false)) &&
    length(flatten([for config in pool.node_config_details : config.placement_configs])) > 0
  ]
  preferred_pools  = [for pool in local.compatible_pools : pool if alltrue([for placement in flatten([for config in pool.node_config_details : config.placement_configs]) : placement.availability_domain == var.expected.availability_domain])]
  matching_pools   = length(local.preferred_pools) == 1 ? local.preferred_pools : local.compatible_pools
  selected_pool_id = var.gpu_pool_id != null ? var.gpu_pool_id : try(one([for pool in local.matching_pools : pool.id]), null)
  cluster          = data.oci_containerengine_cluster.target
  pool             = try(data.oci_containerengine_node_pool.selected[0], null)
  selected_labels  = local.pool == null ? {} : { for label in local.pool.initial_node_labels : label.key => label.value }
  platform_name    = coalesce(try(local.selected_labels["oke-llm/allocation"], null), local.platform_override, "llm-platform")
  pools            = [for pool in data.oci_containerengine_node_pools.cluster.node_pools : pool if pool.state == "ACTIVE"]
  cpu_pools        = [for pool in local.pools : pool if !strcontains(pool.node_shape, "GPU")]
  network_pools    = length(local.cpu_pools) > 0 ? local.cpu_pools : local.pools
  configs          = flatten([for pool in local.network_pools : pool.node_config_details])
  worker_subnets   = distinct(flatten([for config in local.configs : [for placement in config.placement_configs : placement.subnet_id]]))
  endpoint_subnet  = try(local.cluster.endpoint_config[0].subnet_id, null)
  # An ambiguous worker network requires an explicit override. Only a cluster
  # without any known worker network falls back to its own endpoint subnet.
  runner_subnet = try(coalesce(var.runner_subnet_id, length(local.worker_subnets) == 0 ? local.endpoint_subnet : try(one(local.worker_subnets), null)), null)
  nsg_sets = distinct([for config in local.configs : sort(config.nsg_ids)
    if anytrue([for placement in config.placement_configs : placement.subnet_id == local.runner_subnet])
  ])
  nsg_override = distinct([for value in coalesce(var.runner_nsg_ids, []) : trimspace(value) if try(trimspace(value) != "", false)])
  runner_nsgs  = length(local.nsg_override) > 0 ? local.nsg_override : try(coalesce(one(local.nsg_sets), []), [])
  subnet_ids   = toset(compact([local.runner_subnet]))
}
data "oci_core_subnet" "runner" {
  for_each  = local.subnet_ids
  subnet_id = each.key
}
data "oci_core_network_security_group" "runner" {
  for_each                  = toset(local.runner_nsgs)
  network_security_group_id = each.key
}
# The selected allocation identifies the trusted platform. Search only its
# pool/cluster/model-project compartments, never unrelated tenancy projects.
data "oci_devops_deploy_pipelines" "model_onboarding" {
  for_each       = local.pool == null ? toset([]) : toset(compact([local.pool.compartment_id, local.cluster.compartment_id, var.compartment_id]))
  compartment_id = each.key
  display_name   = "${local.platform_name}-model-onboarding"
  state          = "ACTIVE"
}
locals {
  onboarding_pipelines = merge({}, [for compartment, result in data.oci_devops_deploy_pipelines.model_onboarding : {
    for pipeline in flatten([for collection in result.deploy_pipeline_collection : collection.items]) : pipeline.id => pipeline
    if pipeline.compartment_id == compartment && pipeline.display_name == "${local.platform_name}-model-onboarding" && pipeline.state == "ACTIVE"
  }]...)
}
data "oci_devops_project" "platform" {
  for_each   = toset([for pipeline in local.onboarding_pipelines : pipeline.project_id])
  project_id = each.key
}
data "oci_devops_deploy_stages" "model_onboarding" {
  for_each           = local.onboarding_pipelines
  deploy_pipeline_id = each.key
}
locals {
  onboarding_stages = { for id, result in data.oci_devops_deploy_stages.model_onboarding : id => [
    for stage in flatten([for collection in result.deploy_stage_collection : collection.items]) : stage
    if !contains(["DELETING", "DELETED"], stage.state)
  ] }
  # ListStages omits common fields in the pinned provider. Use summary identity
  # only, then verify the full stage/pipeline binding from GetDeployStage.
  onboarding_candidates = { for id, stages in local.onboarding_stages : id => stages[0]
    if try(length(stages) == 1 && stages[0].state == "ACTIVE" && stages[0].deploy_stage_type == "SHELL" && trimspace(stages[0].id) != "", false)
  }
}
data "oci_devops_deploy_stage" "model_onboarding" {
  for_each        = local.onboarding_candidates
  deploy_stage_id = each.value.id
}
locals {
  onboarding_sources = { for id, stage in data.oci_devops_deploy_stage.model_onboarding : id => stage
    if try(stage.state == "ACTIVE" && stage.deploy_stage_type == "SHELL" && stage.deploy_pipeline_id == id && trimspace(stage.command_spec_deploy_artifact_id) != "", false)
  }
}
data "oci_devops_deploy_artifact" "model_onboarding" {
  for_each           = toset([for stage in local.onboarding_sources : stage.command_spec_deploy_artifact_id])
  deploy_artifact_id = each.key
}
locals {
  onboarding_artifacts = { for id, stage in local.onboarding_sources : id => data.oci_devops_deploy_artifact.model_onboarding[stage.command_spec_deploy_artifact_id] }
  # The OCI provider exposes decoded []byte text despite this field's name.
  onboarding_content = { for id, artifact in local.onboarding_artifacts : id => try(artifact.deploy_artifact_source[0].base64encoded_content, "") }
  onboarding_env     = { for id, content in local.onboarding_content : id => try(yamldecode(content).env.variables, {}) }
  trusted_onboarding = { for id, stage in local.onboarding_sources : id => {
    pipeline_id = id, project_id = local.onboarding_pipelines[id].project_id,
    revision    = sha256(jsonencode({ pipeline_id = id, stage_id = stage.id, artifact_id = stage.command_spec_deploy_artifact_id, content = sha256(local.onboarding_content[id]) }))
    } if try(
    data.oci_devops_project.platform[local.onboarding_pipelines[id].project_id].name == local.platform_name &&
    data.oci_devops_project.platform[local.onboarding_pipelines[id].project_id].state == "ACTIVE" &&
    stage.project_id == local.onboarding_pipelines[id].project_id &&
    local.onboarding_artifacts[id].project_id == local.onboarding_pipelines[id].project_id &&
    local.onboarding_artifacts[id].state == "ACTIVE" && local.onboarding_artifacts[id].deploy_artifact_type == "COMMAND_SPEC" &&
    local.onboarding_artifacts[id].argument_substitution_mode == "NONE" &&
    local.onboarding_artifacts[id].deploy_artifact_source[0].deploy_artifact_source_type == "INLINE" &&
    local.onboarding_env[id].CLUSTER_ID == var.cluster_id && local.onboarding_env[id].PLATFORM_NAME == local.platform_name &&
    local.onboarding_env[id].PROJECT_ID == local.onboarding_pipelines[id].project_id &&
    alltrue([for name in ["MODEL_NAMESPACE", "MODEL_PIPELINE_IDS", "MODEL_PROJECT_ID", "MODEL_GPU_POOL_ID", "MODEL_ACCESS_OPERATION"] :
      contains(flatten([for parameters in local.onboarding_pipelines[id].deploy_pipeline_parameters : [for item in parameters.items : item.name]]), name)
    ]), false)
  }
  model_onboarding = try(one(values(local.trusted_onboarding)), null)
}
locals {
  issues = compact([
    local.cluster.state == "ACTIVE" ? "" : "The selected cluster must be ACTIVE.",
    local.pool == null ? "No retained GPU pool matches this model. Apply the infrastructure stack first, or select the matching managed GPU pool." : "",
    local.pool == null ? "" : length(local.trusted_onboarding) == 0 ? "No ACTIVE trusted model-onboarding pipeline matches the selected platform and cluster. Apply the infrastructure/components stack first; its project and onboarding pipeline must be accessible in the pool, cluster or model-project compartment." : length(local.trusted_onboarding) > 1 ? "Multiple trusted model-onboarding pipelines match this platform and cluster. Remove duplicate platform deployments before automatic model deployment." : "",
    var.gpu_pool_id == null && length(local.matching_pools) > 1 ? "Multiple compatible managed GPU pools match this cluster and shape; choose a GPU pool OCID or explicit platform-name override." : "",
    can(regex("^[a-z][a-z0-9-]{0,39}$", local.platform_name)) ? "" : "The selected allocation label must be a lowercase platform DNS name.",
    local.runner_subnet == null ? "No unambiguous runner subnet: choose a subnet in the existing cluster VCN." : "",
    length(local.nsg_override) == 0 && length(local.nsg_sets) > 1 ? "Worker pools use different NSG policies; select runner_nsg_ids explicitly." : "",
    local.runner_subnet == null ? "" : data.oci_core_subnet.runner[local.runner_subnet].vcn_id == local.cluster.vcn_id ? "" : "Runner subnet belongs to a different VCN.",
    alltrue([for nsg in data.oci_core_network_security_group.runner : nsg.vcn_id == local.cluster.vcn_id]) ? "" : "Runner NSGs must belong to the cluster VCN.",
    local.runner_subnet == null ? "" : try(length(data.oci_core_subnet.runner[local.runner_subnet].ipv6cidr_blocks) > 0, false) ? "OCI DevOps private OKE environments require an IPv4-only runner subnet." : "",
    local.pool == null ? "" : local.pool.cluster_id == var.cluster_id ? "" : "Selected GPU pool belongs to a different OKE cluster.",
    local.pool == null ? "" : local.pool.node_shape == var.expected.gpu_shape ? "" : "Selected GPU pool shape differs from the frozen model assessment; choose a matching discovery option.",
    local.pool == null ? "" : try(coalesce(local.pool.freeform_tags["oke-llm-allocation"], ""), "") != "" ? "" : "Selected pool is not an owned retained allocation (missing oke-llm-allocation tag).",
    local.pool == null ? "" : contains(keys(local.selected_labels), "oke-llm/allocation") ? "" : "Selected pool has no oke-llm/allocation label. Use an infrastructure-managed pool or arrange an explicit trusted pool-label integration before model deployment.",

    var.expected.node_count >= 1 && var.expected.gpu_count_per_host >= 1 && var.expected.gpu_shape != "" && var.expected.availability_domain != "" ? "" : "The model specification must include a GPU shape, positive host count and GPUs per host."
  ])
}
output "target" {
  value = {
    binding_mode                 = "runtime", platform_name = local.platform_name,
    model_onboarding_pipeline_id = try(local.model_onboarding.pipeline_id, null), model_onboarding_project_id = try(local.model_onboarding.project_id, null),
    model_onboarding_revision    = try(local.model_onboarding.revision, null),
    cluster_id                   = var.cluster_id, cluster_compartment_id = local.cluster.compartment_id, cluster_type = local.cluster.type,
    kubernetes_version           = local.cluster.kubernetes_version, vcn_id = local.cluster.vcn_id,
    runner_subnet_id             = local.runner_subnet, runner_nsg_ids = local.runner_nsgs,
    runner_subnet_choices        = local.worker_subnets, cpu_shapes = sort(distinct([for pool in local.cpu_pools : pool.node_shape])),
    gpu_pool_compartment_id      = try(coalesce(try(local.pool.compartment_id, null), var.gpu_pool_compartment_id, local.cluster.compartment_id), local.cluster.compartment_id),
    gpu_selector                 = "oke-llm/allocation=${local.platform_name}", gpu_shape = var.expected.gpu_shape,
    availability_domain          = try(one(distinct(flatten([for config in local.pool.node_config_details : [for placement in config.placement_configs : placement.availability_domain]]))), var.expected.availability_domain), gpu_count_per_host = var.expected.gpu_count_per_host,
    expected_availability_domain = var.expected.availability_domain,
    pool_availability_domains    = local.pool == null ? [] : distinct(flatten([for config in local.pool.node_config_details : [for placement in config.placement_configs : placement.availability_domain]])),
    expected_node_count          = var.expected.node_count,
    node_count                   = local.pool == null ? var.expected.node_count : max(var.expected.node_count, try(local.pool.node_config_details[0].size, 0)),
    allocation = {
      gpu_pool_id        = local.selected_pool_id, allocation_identity = try(local.pool.freeform_tags["oke-llm-allocation"], null),
      compute_cluster_id = try(local.pool.node_config_details[0].compute_cluster_id, null)
    },
    metadata_ready        = length(local.issues) == 0, issues = local.issues,
    matching_gpu_pool_ids = [for pool in local.matching_pools : pool.id], pool_binding = local.selected_pool_id == null ? "deferred" : var.gpu_pool_id == null ? "inferred_unique_managed_pool" : "explicit_managed_pool",
    gpu_readiness         = "pending_automatic_model_pipeline; requires_an_existing_retained_pool",
    free_gpu_headroom     = "unknown_other_namespace_requests_not_visible"
  }
}
