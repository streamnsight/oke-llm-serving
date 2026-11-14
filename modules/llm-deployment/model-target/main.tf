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
locals {
  issues = compact([
    local.cluster.state == "ACTIVE" ? "" : "The selected cluster must be ACTIVE.",
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
    gpu_readiness         = "deferred_to_pipeline; model resource creation does not require allocated or Ready GPU nodes",
    free_gpu_headroom     = "unknown_other_namespace_requests_not_visible"
  }
}
