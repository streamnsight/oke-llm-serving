<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# OKE-managed GPU add-ons

Infrastructure Apply enables missing hardware add-ons on the selected enhanced OKE cluster, before GPU allocation. This also runs with `skip_gpu_allocation=true`; it needs OCI API access, not kubectl access to the private Kubernetes endpoint. The applying principal needs OKE add-on installation permissions for this cluster.

- Enable Node Feature Discovery first.
- Reuse the existing NVIDIA GPU Plugin or GPU Operator, preserving its settings. With neither installed, prefer the compatible OKE NVIDIA GPU Operator; fall back to the OKE NVIDIA Device Plugin if the Operator is unavailable.
- Enable NVIDIA Network Operator only for the selected RDMA path.
- Enable the GPU Health Monitoring controller for a bare-metal shape when OKE lists an ACTIVE compatible option. This does not create a `GpuHealthMonitoringConfig`, configure a host agent, or enable any node repair policy.
- Do not install AMD components for this NVIDIA-only deployment path.

OKE supplies the latest compatible default version for new installations. Existing versions, configuration and auto-update settings are preserved. Existing failed add-ons and an explicitly disabled Operator device plugin produce an actionable error instead of being overwritten. In-progress installations are awaited. The helper re-reads live inventory before installation and uses `isOverrideExisting=false` to avoid replacing an installation enabled concurrently.

The module uses native Terraform data sources for compatible versions and inventory. A module-local Bash/OCI CLI ensure step performs installations: the Terraform provider's `oci_containerengine_addon` resource calls DisableAddon on destroy, even when `remove_addon_resources_on_delete=false`. Taking ownership would risk disabling a cluster-shared installation. This module has no destroy action; newly enabled and reused add-ons remain managed by OKE after stack removal. Disable them explicitly through OKE only when no remaining workload needs them.

An observed hardware add-on change can cause the ensure step to run again. The first refresh after installation can therefore schedule one further no-op ensure; it does not reinstall or upgrade enabled add-ons. Unchanged inventories produce no ensure replacement. There is no perpetual timestamp trigger.

Local runs use OCI CLI credentials/profile; RMS uses its delegated or principal authentication, following the same handling as discovery and repository cleanup. Tokens are read at runtime and are not placed in Terraform configuration or state.

ACTIVE is a service installation check. Validate full GPU allocatable counts, CUDA, pod RDMA devices, network configuration and NCCL on real nodes. GPU health monitoring additionally needs a non-overlapping per-pool `GpuHealthMonitoringConfig` and a compatible Oracle Cloud Agent. DCGM exporter scraping into Prometheus remains separate; reusing a standalone GPU Plugin does not imply that an exporter exists. No duplicate Helm GPU/Network Operators or automatic repair policy are installed here.

Sources: [OKE add-ons](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengintroducingclusteraddons.htm), [GPU Operator configuration](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/configuration-arguments-nvidia-gpu-operator.htm), [GPU health configuration](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengautorepairgpuworkernodes.htm), [provider add-on lifecycle](https://github.com/oracle/terraform-provider-oci/blob/master/internal/service/containerengine/containerengine_addon_resource.go).
