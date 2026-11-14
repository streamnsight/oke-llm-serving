# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  addon_inventory_available = data.oci_containerengine_cluster.target.type == "ENHANCED_CLUSTER"
  addon_inventory = [for addon in try(data.oci_containerengine_addons.target[0].addons, []) : {
    name              = addon.addon_name
    normalized_name   = replace(lower(addon.addon_name), "/[^a-z0-9]/", "")
    state             = addon.state
    installed_version = addon.current_installed_version
    configurations    = { for configuration in coalesce(addon.configurations, []) : configuration.key => configuration.value }
  }]
  # Reuse the service integration. Do not install a competing standalone plugin,
  # infer a version, or confuse add-on ACTIVE with functioning node devices.
  usable_gpu_addons = [for addon in local.addon_inventory : addon if addon.state == "ACTIVE" && (
    contains(["nvidiadeviceplugin", "nvidiagpuplugin"], addon.normalized_name) ||
    (addon.normalized_name == "nvidiagpuoperator" && lower(trimspace(coalesce(lookup(addon.configurations, "devicePlugin.enabled", null), "true"))) != "false")
  )]
  gpu_addons            = [for addon in local.addon_inventory : addon if contains(["nvidiadeviceplugin", "nvidiagpuplugin", "nvidiagpuoperator"], addon.normalized_name)]
  network_addons        = [for addon in local.addon_inventory : addon if addon.normalized_name == "nvidianetworkoperator"]
  active_network_addons = [for addon in local.network_addons : addon if addon.state == "ACTIVE"]
  addon_prerequisite_failures = compact([
    local.addon_inventory_available && length(local.usable_gpu_addons) == 0 ? "No ACTIVE OKE NVIDIA GPU Plugin or GPU Operator with its device plugin enabled was found. Enable or repair the OKE NVIDIA GPU Plugin for ordinary full-GPU allocation, or reuse a configured OKE GPU Operator. GPU images do not install optional cluster add-ons. Do not install a competing device plugin; inspect add-on state and devicePlugin.enabled before retrying." : "",
    var.requires_rdma && local.addon_inventory_available && length(local.active_network_addons) == 0 ? "This stack's managed pod-RDMA path requires an ACTIVE OKE NVIDIA Network Operator. Enable or repair its image-compatible network configuration before allocating retained Compute Cluster/GPU resources. Compute Cluster placement enables host Oracle Cloud Agent RDMA plugins, not Kubernetes pod-device exposure. Manual RDMA integrations may exist but are not assessed by this path." : ""
  ])
  addon_prerequisites = {
    schema_version = "1.0"
    ready          = length(local.addon_prerequisite_failures) == 0
    status         = !local.addon_inventory_available ? "unverified_basic_cluster" : length(local.addon_prerequisite_failures) > 0 ? "blocked_native_addon_prerequisites" : "native_addons_active_runtime_unverified"
    scope          = "Service add-on state and explicit device-plugin configuration only; not a GPU, CUDA or RDMA runtime test."
    management     = "reuse_only_no_addon_creation_or_configuration_changes"
    gpu = {
      status = !local.addon_inventory_available ? "not_assessed" : length(local.usable_gpu_addons) > 0 ? "native_device_plugin_active_runtime_unverified" : "missing_or_unusable_native_device_plugin"
      observed_addons = [for addon in local.gpu_addons : {
        name                              = addon.name, state = addon.state, installed_version = addon.installed_version,
        device_plugin_explicitly_disabled = addon.normalized_name == "nvidiagpuoperator" && lower(trimspace(coalesce(lookup(addon.configurations, "devicePlugin.enabled", null), "true"))) == "false"
      }]
      required_runtime_check = "Ready pool nodes must advertise the full shape's nvidia.com/gpu allocatable count; validate CUDA separately. Basic-cluster or manually managed device plugins require independent Kubernetes validation."
    }
    rdma = {
      required                 = var.requires_rdma
      host_agent_configuration = var.requires_rdma ? "OKE enables Oracle Cloud Agent HPC RDMA Authentication and Auto-Configuration for Compute Cluster node pools." : "not_required"
      network_addon_status     = !var.requires_rdma ? "not_required" : !local.addon_inventory_available ? "not_assessed" : length(local.active_network_addons) > 0 ? "active_configuration_unverified" : "missing_or_inactive"
      pod_device_exposure      = var.requires_rdma ? "unverified_until_gpu_nodes_advertise_selected_extended_rdma_resource" : "not_required"
      observed_addons = [for addon in local.network_addons : {
        name             = addon.name, state = addon.state, installed_version = addon.installed_version,
        sriov_enabled    = try(tobool(addon.configurations["sriovNetworkOperator.enabled"]), null),
        vf_creation_mode = lookup(addon.configurations, "vfCreationMode", null)
      }]
      required_runtime_check = "Validate the selected pod RDMA device resource on every participating host, then run transport/NCCL tests. ACTIVE Network Operator alone does not prove configured SR-IOV, device exposure or GPUDirect RDMA."
    }
    gpu_metrics = {
      status = "exporter_endpoint_and_prometheus_scraping_not_verified"
      operator_configuration = [for addon in local.gpu_addons : {
        name                    = addon.name,
        exporter_enabled        = try(tobool(addon.configurations["dcgmExporter.enabled"]), null),
        service_monitor_enabled = try(tobool(addon.configurations["dcgmExporter.serviceMonitor.enabled"]), null)
      } if addon.normalized_name == "nvidiagpuoperator"]
      remaining_work = "Reuse an available DCGM exporter and configure a matching ServiceMonitor/scrape target. GPU device capacity and DCGM host-engine presence do not establish a Prometheus metrics endpoint."
    }
    blocking_reasons = local.addon_prerequisite_failures
    diagnostics = concat(
      !local.addon_inventory_available ? ["Basic cluster: native optional add-on inventory was not queried. Device-plugin availability is unknown; allocation preflight does not assert readiness."] : [],
      length(local.usable_gpu_addons) > 1 ? ["Multiple ACTIVE GPU add-ons were observed; verify their configurations and ownership do not run competing device plugins. This check does not infer a conflict from names alone."] : [],
      ["This module never changes an add-on version, driver, configuration or retained pool launch binding."]
    )
    sources = [
      "https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengintroducingclusteraddons.htm",
      "https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengusingcomputeclusters.htm",
      "https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/configuration-arguments-nvidia-gpu-operator.htm",
      "https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/configuration-arguments-nvidia-network-operator.htm"
    ]
  }
}

output "addon_prerequisites" {
  description = "Read-only OKE-native prerequisite evidence; ACTIVE add-ons do not establish live GPU, metrics or RDMA readiness."
  value       = local.addon_prerequisites
}
