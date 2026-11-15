# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12" } }
}
variable "cluster_id" { type = string }
variable "cluster_type" { type = string }
variable "kubernetes_version" { type = string }
variable "region" { type = string }
variable "gpu_shape" { type = string }
variable "requires_rdma" { type = bool }
variable "installed_addons" {
  type = list(object({ name = string, state = string, configurations = map(string) }))
}
data "oci_containerengine_addon_options" "compatible" {
  kubernetes_version = var.kubernetes_version
}
locals {
  supported = sort([for option in data.oci_containerengine_addon_options.compatible.addon_options : option.name
  if option.state == "ACTIVE" && anytrue([for version in option.versions : version.status == "ACTIVE"])])
  health_supported = startswith(var.gpu_shape, "BM.GPU") && contains(local.supported, "GpuHealthMonitoring")
  observed = sort([for addon in var.installed_addons : jsonencode(addon)
  if contains(["nodefeaturediscovery", "nvidiagpuoperator", "nvidiadeviceplugin", "nvidiagpuplugin", "nvidianetworkoperator", "gpuhealthmonitoring"], replace(lower(addon.name), "/[^a-z0-9]/", ""))])
}
# The provider's Addon resource calls DisableAddon on Destroy, even with
# remove_addon_resources_on_delete=false. These are shared, retained services:
# ensure missing installations without taking ownership of existing settings.
resource "terraform_data" "ensure" {
  input = { cluster_id = var.cluster_id }
  triggers_replace = {
    cluster_id = var.cluster_id, requires_rdma = var.requires_rdma,
    health     = local.health_supported, supported = local.supported,
    observed   = local.observed, script = filesha256("${path.module}/scripts/ensure-addons.sh")
  }
  provisioner "local-exec" {
    command = "bash '${path.module}/scripts/ensure-addons.sh'"
    environment = {
      CLUSTER_ID            = var.cluster_id, REGION = var.region,
      REQUIRES_RDMA         = tostring(var.requires_rdma), INSTALL_GPU_HEALTH = tostring(local.health_supported),
      SUPPORTED_ADDONS_JSON = jsonencode(local.supported)
    }
  }
  lifecycle {
    precondition {
      condition     = var.cluster_type == "ENHANCED_CLUSTER"
      error_message = "Automatic OKE-managed GPU add-on installation requires an enhanced cluster."
    }
  }
  # No destroy provisioner: shared add-ons remain enabled after stack removal.
}
data "oci_containerengine_addons" "enabled" {
  cluster_id = terraform_data.ensure.output.cluster_id
}
output "cluster_id" {
  description = "Dependency binding: allocation reads native prerequisites after installation completes."
  value       = terraform_data.ensure.output.cluster_id
}
output "status" {
  value = {
    management             = "enable_missing_reuse_existing_retain_on_destroy"
    version_selection      = "OKE latest compatible default for new installs; existing versions and settings preserved"
    rdma_required          = var.requires_rdma
    health_addon_requested = local.health_supported
    health_scope           = "Controller only; per-pool GpuHealthMonitoringConfig and host-agent validation remain separate. No repair policy is created."
    addons = [for addon in data.oci_containerengine_addons.enabled.addons : {
      name = addon.addon_name, state = addon.state, installed_version = addon.current_installed_version
    } if contains(["nodefeaturediscovery", "nvidiagpuoperator", "nvidiadeviceplugin", "nvidiagpuplugin", "nvidianetworkoperator", "gpuhealthmonitoring"], replace(lower(addon.addon_name), "/[^a-z0-9]/", ""))]
    runtime_readiness = "not_verified_by_addon_installation"
  }
}
