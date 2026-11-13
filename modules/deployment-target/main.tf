# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12" } }
}
variable "cluster_id" { type = string }
variable "availability_domain" { type = string }
variable "gpu_shape" { type = string }
variable "gpu_architecture" { type = string }
variable "cpu_shape" { type = string }
variable "resolve_cpu_image" {
  description = "False when the caller reuses existing CPU pools."
  type        = bool
  default     = true
}
variable "os_version" { type = string }
variable "requires_rdma" {
  type    = bool
  default = false
}
variable "worker_nsg_ids" {
  type    = list(string)
  default = null
}
variable "pod_nsg_ids" {
  type    = list(string)
  default = null
}
variable "devops_nsg_ids" {
  type    = list(string)
  default = null
}
variable "overrides" { type = object({ gpu_image_id = string, cpu_image_id = string, subnet_id = string, cpu_subnet_id = string, devops_subnet_id = string, pod_subnet_id = string }) }
data "oci_containerengine_cluster" "target" { cluster_id = var.cluster_id }
data "oci_containerengine_node_pools" "target" {
  compartment_id = data.oci_containerengine_cluster.target.compartment_id
  cluster_id     = var.cluster_id
}
data "oci_containerengine_addons" "target" {
  count      = data.oci_containerengine_cluster.target.type == "ENHANCED_CLUSTER" ? 1 : 0
  cluster_id = var.cluster_id
}
locals {
  cluster         = data.oci_containerengine_cluster.target
  pools           = [for p in data.oci_containerengine_node_pools.target.node_pools : p if p.state == "ACTIVE"]
  worker_ids      = distinct(flatten([for p in local.pools : [for n in p.node_config_details : [for placement in n.placement_configs : placement.subnet_id]]]))
  pod_ids         = distinct(flatten([for p in local.pools : [for n in p.node_config_details : [for o in n.node_pool_pod_network_option_details : o.pod_subnet_ids]]]))
  endpoint_subnet = try(local.cluster.endpoint_config[0].subnet_id, null)
  subnet_ids      = toset(compact(concat(local.worker_ids, local.pod_ids, [local.endpoint_subnet], [for k, v in var.overrides : v if endswith(k, "subnet_id")])))
}
data "oci_core_subnet" "candidate" {
  for_each  = local.subnet_ids
  subnet_id = each.key
}
locals {
  usable_worker_ids = [for id in local.worker_ids : id if data.oci_core_subnet.candidate[id].vcn_id == local.cluster.vcn_id &&
  (try(coalesce(data.oci_core_subnet.candidate[id].availability_domain, ""), "") == "" || data.oci_core_subnet.candidate[id].availability_domain == var.availability_domain)]
  usable_pod_ids = [for id in local.pod_ids : id if data.oci_core_subnet.candidate[id].vcn_id == local.cluster.vcn_id &&
  (try(coalesce(data.oci_core_subnet.candidate[id].availability_domain, ""), "") == "" || data.oci_core_subnet.candidate[id].availability_domain == var.availability_domain)]
  native_cni       = try(local.cluster.cluster_pod_network_options[0].cni_type == "OCI_VCN_IP_NATIVE", false)
  gpu_subnet       = try(coalesce(var.overrides.subnet_id, try(one(local.usable_worker_ids), null)), null)
  cpu_subnet       = try(coalesce(var.overrides.cpu_subnet_id, local.gpu_subnet), null)
  runner_subnet    = try(coalesce(var.overrides.devops_subnet_id, local.cpu_subnet), null)
  pod_subnet       = local.native_cni ? try(coalesce(var.overrides.pod_subnet_id, try(one(local.usable_pod_ids), null)), null) : null
  selected_subnets = { gpu = local.gpu_subnet, cpu = local.cpu_subnet, devops = local.runner_subnet, pod = local.pod_subnet }
  configs          = flatten([for p in local.pools : p.node_config_details])
  worker_nsg_sets  = { for role in ["gpu", "cpu", "devops"] : role => distinct([for n in local.configs : sort(n.nsg_ids) if anytrue([for p in n.placement_configs : p.subnet_id == local.selected_subnets[role]])]) }
  worker_nsgs      = { for role, sets in local.worker_nsg_sets : role => var.worker_nsg_ids != null ? var.worker_nsg_ids : try(coalesce(one(sets), []), []) }
  runner_nsgs      = var.devops_nsg_ids != null ? var.devops_nsg_ids : local.worker_nsgs.devops
  pod_nsg_sets     = distinct([for o in flatten([for n in local.configs : n.node_pool_pod_network_option_details]) : sort(o.pod_nsg_ids) if contains(o.pod_subnet_ids, local.pod_subnet == null ? "" : local.pod_subnet)])
  pod_nsgs         = var.pod_nsg_ids != null ? var.pod_nsg_ids : try(coalesce(one(local.pod_nsg_sets), []), [])
  subnet_checks = { for role, id in local.selected_subnets : role => {
    id         = id, vcn_matches = try(data.oci_core_subnet.candidate[id].vcn_id == local.cluster.vcn_id, false),
    ad_matches = role == "devops" || try(coalesce(data.oci_core_subnet.candidate[id].availability_domain, var.availability_domain) == var.availability_domain, false),
    private    = try(data.oci_core_subnet.candidate[id].prohibit_public_ip_on_vnic, false)
  } if(role != "pod" || local.native_cni) && (role != "cpu" || var.resolve_cpu_image) }
  issues = compact(concat(
    [var.requires_rdma && local.cluster.type != "ENHANCED_CLUSTER" ? "RDMA managed-node placement requires an enhanced OKE cluster." : ""],
    [for role, sets in local.worker_nsg_sets : "Multiple ${role} worker NSG policies; provide an NSG override." if length(sets) > 1 && var.worker_nsg_ids == null && !(role == "devops" && var.devops_nsg_ids != null)],
    [local.native_cni && length(local.pod_nsg_sets) > 1 && var.pod_nsg_ids == null ? "Multiple pod NSG policies; provide pod_nsg_ids." : ""],
    [for role, check in local.subnet_checks : check.id == null ? "No unambiguous ${role} subnet; select an existing subnet override." : !check.vcn_matches ? "${role} subnet belongs to another VCN." : !check.ad_matches ? "${role} subnet is in another availability domain." : ""],
    [module.gpu_image.image.id == null ? "No shape-compatible OKE GPU image for the cluster version and OS." : "", var.resolve_cpu_image && try(module.cpu_image[0].image.id == null, false) ? "No shape-compatible OKE CPU image for the cluster version and OS." : "", local.cluster.state == "ACTIVE" ? "" : "Cluster must be ACTIVE."]
  ))
}
module "gpu_image" {
  source             = "../oke-node-image"
  cluster_id         = var.cluster_id
  compartment_id     = local.cluster.compartment_id
  kubernetes_version = local.cluster.kubernetes_version
  shape              = var.gpu_shape
  architecture       = var.gpu_architecture
  os_version         = var.os_version
  image_id           = var.overrides.gpu_image_id
}
data "oci_core_network_security_group" "selected" {
  for_each                  = toset(concat(local.worker_nsgs.gpu, local.worker_nsgs.cpu, local.runner_nsgs, local.pod_nsgs))
  network_security_group_id = each.key
}
module "cpu_image" {
  count              = var.resolve_cpu_image ? 1 : 0
  source             = "../oke-node-image"
  cluster_id         = var.cluster_id
  compartment_id     = local.cluster.compartment_id
  kubernetes_version = local.cluster.kubernetes_version
  shape              = var.cpu_shape
  architecture       = "amd64"
  os_version         = var.os_version
  image_id           = var.overrides.cpu_image_id
}
output "target" {
  value = {
    cluster_id         = var.cluster_id, cluster_compartment_id = local.cluster.compartment_id, cluster_type = local.cluster.type,
    kubernetes_version = local.cluster.kubernetes_version, vcn_id = local.cluster.vcn_id,
    gpu_image          = module.gpu_image.image, cpu_image = try(module.cpu_image[0].image, null),
    subnet_id          = local.gpu_subnet, cpu_subnet_id = local.cpu_subnet, devops_subnet_id = local.runner_subnet, pod_subnet_id = local.pod_subnet,
    subnet_choices     = { workers = local.usable_worker_ids, pods = local.usable_pod_ids }, subnet_checks = local.subnet_checks,
    gpu_nsg_ids        = local.worker_nsgs.gpu, cpu_nsg_ids = local.worker_nsgs.cpu, devops_nsg_ids = local.runner_nsgs, pod_nsg_ids = local.pod_nsgs,
    endpoint_subnet_id = local.endpoint_subnet, api_connectivity = "requires_routing_security_and_runtime_check",
    native_cni         = local.native_cni, ready = length(local.issues) == 0, issues = local.issues,
    oke_addons         = try([for a in data.oci_containerengine_addons.target[0].addons : { name = a.addon_name, installed_version = a.current_installed_version, state = a.state }], [])
  }
  precondition {
    condition     = alltrue([for nsg in data.oci_core_network_security_group.selected : nsg.vcn_id == local.cluster.vcn_id])
    error_message = "Every selected network security group must belong to the selected cluster's VCN."
  }
  precondition {
    condition     = alltrue([for k, v in var.overrides : try(data.oci_core_subnet.candidate[v].vcn_id == local.cluster.vcn_id, true) if endswith(k, "subnet_id") && v != null])
    error_message = "Every subnet override must belong to the selected cluster's VCN."
  }
}
