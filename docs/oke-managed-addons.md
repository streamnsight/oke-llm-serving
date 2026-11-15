<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# OKE-managed GPU and network support

The infrastructure stack enables missing OKE-managed GPU/network add-ons and reuses existing installations and the selected GPU node image. It does not install duplicate standalone GPU/Network Operators or RDMA plugins. Optional add-ons are not enabled merely by selecting an enhanced cluster, so infrastructure Apply explicitly ensures them before GPU allocation, including in GPU-allocation debug mode. OKE then manages their lifecycle and reconciles their resources. See Oracle's [cluster add-on overview](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengintroducingclusteraddons.htm).

The [native add-on module](../modules/cluster-add-ons/oke-managed-addons/README.md) ensures NFD first, reuses an existing NVIDIA GPU Plugin/Operator, and otherwise enables the compatible Operator (or the native Plugin when the Operator is unavailable). It enables Network Operator only for RDMA and the compatible GPU Health Monitoring controller for bare-metal selections. Existing versions and settings are preserved; shared add-ons remain enabled on stack removal. Basic clusters are rejected for this automatic installation path. Terraform reads `oci_containerengine_addons` after installation and publishes service state separately from runtime readiness. A preinstalled device plugin can supply GPU resources without an Operator.

GPU Health Monitoring controller installation does not enable monitoring for a pool or configure GPU repair. Per-pool `GpuHealthMonitoringConfig`, compatible host-agent configuration and runtime checks remain separate. No `NodeRepairConfig` is created. Reusing a standalone GPU Plugin also does not establish a DCGM exporter or Prometheus scraping.

Before deploying, validating or benchmarking a model, the pipeline waits for enough Ready nodes advertising `nvidia.com/gpu` with at least the requested tensor-parallel GPU count per host. Model pods tolerate OKE's GPU `NoSchedule` taint. Missing capabilities produce a failed stage with node and capability reports archived to the evidence bucket.

For an RDMA selection, configure the existing OKE network support for the selected shape first. Oracle's [Network Operator options](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/configuration-arguments-nvidia-network-operator.htm) include SR-IOV and VF creation settings; enabling the operator alone does not establish a usable RDMA network.

- Leave `rdma_resource_name` unset when exactly one advertised RDMA resource is available across enough GPU nodes. The pipeline detects resources under `rdma/` or NVIDIA names containing `rdma`/`roce` and requests that resource in each model pod.
- Set `rdma_resource_name` explicitly when several resources exist or the configured name does not identify RDMA. The stack checks that the selected resource is advertised on enough nodes; it cannot establish a custom resource's networking semantics from its name.
- If the cluster configuration requires a Multus network attachment, set `rdma_network_attachment` to an existing NetworkAttachmentDefinition name or `namespace/name`. The deploy stage checks that it exists and adds the pod annotation. Network policies, NADs, VF configuration and any additional privileges remain the existing cluster network configuration's responsibility.

Advertised resources are a readiness check, not proof of GPUDirect, fabric connectivity or CUDA/driver compatibility. Deployment validation still needs real inference and NCCL RDMA evidence. A newer serving image alone does not establish that a newer GPU Operator is necessary. There is currently no automatic minimum add-on version resolver: a demonstrated compatibility gap must be addressed through the OKE add-on/node-image lifecycle, with runtime validation, rather than installing a second operator. Oracle documents [GPU Operator configuration and device-plugin controls](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/configuration-arguments-nvidia-gpu-operator.htm).
