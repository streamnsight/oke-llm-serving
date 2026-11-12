<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# OKE-managed GPU and network support

The deployment stack reuses GPU/network support provided by OKE-managed add-ons and the selected GPU node image. It does not install another GPU Operator or RDMA device plugin. Enhanced OKE supports optional NVIDIA GPU and Network Operator add-ons, but optional add-ons are not enabled merely by selecting an enhanced cluster. OKE manages their lifecycle and reconciles their resources. See Oracle's [cluster add-on overview](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengintroducingclusteraddons.htm).

For an enhanced cluster, Terraform reads `oci_containerengine_addons` and includes each add-on's installed/requested version and state in the allocation output and DevOps configuration. It does not enable or upgrade add-ons. A preinstalled device plugin can also supply GPU resources without an installed GPU Operator; runtime readiness depends on the actual allocation nodes rather than a particular add-on name.

Before deploying, validating or benchmarking a model, the pipeline waits for enough Ready nodes advertising `nvidia.com/gpu` with at least the requested tensor-parallel GPU count per host. Model pods tolerate OKE's GPU `NoSchedule` taint. Missing capabilities produce a failed stage with node and capability reports archived to the evidence bucket.

For an RDMA selection, configure the existing OKE network support for the selected shape first. Oracle's [Network Operator options](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/configuration-arguments-nvidia-network-operator.htm) include SR-IOV and VF creation settings; enabling the operator alone does not establish a usable RDMA network.

- Leave `rdma_resource_name` unset when exactly one advertised RDMA resource is available across enough GPU nodes. The pipeline detects resources under `rdma/` or NVIDIA names containing `rdma`/`roce` and requests that resource in each model pod.
- Set `rdma_resource_name` explicitly when several resources exist or the configured name does not identify RDMA. The stack checks that the selected resource is advertised on enough nodes; it cannot establish a custom resource's networking semantics from its name.
- If the cluster configuration requires a Multus network attachment, set `rdma_network_attachment` to an existing NetworkAttachmentDefinition name or `namespace/name`. The deploy stage checks that it exists and adds the pod annotation. Network policies, NADs, VF configuration and any additional privileges remain the existing cluster network configuration's responsibility.

Advertised resources are a readiness check, not proof of GPUDirect, fabric connectivity or CUDA/driver compatibility. Deployment validation still needs real inference and NCCL RDMA evidence. A newer serving image alone does not establish that a newer GPU Operator is necessary. There is currently no automatic minimum add-on version resolver: a demonstrated compatibility gap must be addressed through the OKE add-on/node-image lifecycle, with runtime validation, rather than installing a second operator. Oracle documents [GPU Operator configuration and device-plugin controls](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/configuration-arguments-nvidia-gpu-operator.htm).
