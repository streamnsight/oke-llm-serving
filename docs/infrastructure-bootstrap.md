<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# GPU infrastructure and independent components

Discovery publishes a configured infrastructure ZIP per confirmed GPU/AD/region choice. The ZIP sets editable Terraform declaration defaults and matching RMS schema defaults. Select an existing OKE cluster in that region; its worker/pod networks and image options are inspected. The stack uses existing CPU pools and creates no CPU node pool.

Keep one stable platform owner per cluster. GPU allocation is independent of component delivery. `skip_gpu_allocation=true` is a temporary debugging control: DevOps resources and CPU component pipelines are still created. Never turn it on after allocating a pool. GPU pools and Compute Clusters retain destroy protection. Launch bindings are frozen after first Apply so a later image/version lookup cannot silently cycle retained GPUs. A maintenance procedure is needed to change those bindings.

RDMA follows the selected model execution/transfer topology and hardware/region support. A single-host H100 layout does not allocate a Compute Cluster simply because its shape supports RDMA. Explicit RDMA placement still needs enhanced OKE, capacity, compatible images/add-ons and fabric validation. IAM policies, including the Compute Cluster launch policy, use the tenancy home-region provider.

## Components and defaults

| Capability | Default | Delivery |
| --- | --- | --- |
| Prometheus/operator and monitoring CRDs | On | Native Helm; persistent 50-GiB data claim, 24-hour retention, editable parameters |
| KEDA and external metrics API | Off, opt in | Independent native Helm; model-specific scalers come later |
| LWS / DisaggregatedSet | Required by selected topology | Independent native Helm plus explicit owned raw-CRD preparation |
| GPU/network operators | Reuse OKE capabilities | Missing/inactive native GPU support blocks enhanced-cluster allocation; the managed RDMA path also requires Network Operator. No duplicate standalone operator |
| Router, LMCache instances, serving replicas and ScaledObjects | Model layer | Not installed by infrastructure bootstrap |
| Optional model-data staging | Direct Hub download by default | Separate retained bucket and CPU download Job pipeline when configured |

Prometheus and KEDA controllers can install concurrently: KEDA installation does not require a live Prometheus endpoint. A model's later scaling configuration must validate that endpoint and its query. KEDA queries Prometheus directly; this does not require a separate Prometheus Adapter. Node autoscaling is not enabled.

OKE's GPU/network add-ons are optional. The allocation preflight checks existing service configuration and publishes `allocation.addon_prerequisites`; it does not enable or upgrade missing add-ons. Basic-cluster/manual integrations remain unverified. An ACTIVE Network Operator does not prove pod RDMA devices are configured, and GPU metric exporter/scrape configuration remains unfinished. Compute Cluster placement configures host RDMA agents separately. Runtime checks must still verify advertised devices, CUDA and fabric operation.

Images and bundled dependencies come from each Helm chart. Module-local chart versions freeze the platform recommendation; the recipe-selected vLLM image is a separate runtime decision. Chart mirroring and the native stage share the editable `CHART_VERSION` argument. Updating component charts is an explicit deployment operation, not an automatic consequence of looking up a newer model recipe.

## Run the pipelines

1. Review Terraform Plan, then Apply. This creates pipelines; it does not start installations automatically.
2. The default `cluster_authorization_mode=iam` grants pipeline principals Kubernetes administration through `CLUSTER_MANAGE`, scoped to this exact cluster. It grants no OCI cluster update/delete or node-pool permissions. For explicit Kubernetes RBAC instead, select `rbac` and review/apply `bootstrap_rbac` as cluster administrator. Both stage types also need private API connectivity; the stack supplies a private OKE environment and a separate private Shell runner channel.
3. Run `platform.bootstrap_pipeline_id` to coordinate the selected component graph, or invoke any `component_pipeline_ids` independently. Independent components start concurrently; each pipeline checks its own release prerequisites. Run settings on the component pipeline are editable and used by both preflight and native Helm.
4. Run `platform.validation_pipeline_id` for fresh, read-only checks. It verifies current releases, managed ownership/generation markers, controller rollouts, Prometheus StatefulSet/PVC readiness and KEDA API aggregation when selected. GPU debug mode records its reduced scope and does not wait for GPUs.
5. Inspect immutable reports in `platform.result_repository_id`. Component report paths include component generation, deployment OCID and operation; platform validation reports have a unique execution version. There is no shared mutable `latest` readiness marker.

Scripts, command specs, values and specifications are immutable Generic Artifact Registry files supplied through native artifact inputs. Charts are mirrored into private OCIR repositories for native `OKE_HELM_CHART_DEPLOYMENT` stages. No models or new readiness reports are stored in a platform artifact bucket. Object Storage remains the discovery ZIP/PAR transport and optional model-data storage.

The code uses readable Shell files and explicit environment exports. Native chart values use `${PARAMETER}` placeholders. `COMMAND_SPEC` artifacts use substitution mode `NONE`; Shell resolves its environment bindings. Neither scripts nor configuration are decoded from a base64 payload inside a command. The OCI INLINE API wrapper for the small coordinator command specification uses the service's required base64 encoding of YAML.

## Ownership, upgrades and teardown

Set component lifecycle modes to `managed`, `reuse` or `retire`. Reuse creates validation only, with no mutating native stage, ownership adoption or uninstall pipeline. Managed delivery refuses an existing foreign release or raw CRD. Resolve ownership explicitly instead of automatically adopting shared resources.

Managed operations acquire an atomic Kubernetes Lease for the cluster/namespace/release and keep it across the native Helm stage. Other components can run concurrently. Failed or interrupted native stages deliberately retain that lease. Explicit recovery requires the old deployment OCID, its terminal OCI status and lease expiry; expiry alone never grants takeover. See [component delivery](../modules/shared/component-delivery/README.md) for the recovery contract.

To remove a managed component, keep its declaration in `retire` mode, Apply, then run its separate `undeploy_pipeline_ids` entry with `CONFIRM_UNINSTALL=true`. Removal checks exact ownership and external dependents. Ordinary uninstall preserves namespaces, CRDs, PVCs, model data and GPU allocations. KEDA's templated CRDs have Helm keep annotations. Raw LWS/Prometheus CRDs are created/updated explicitly using server-side apply without forced field conflicts. Chart CRD upgrades are not assumed to happen automatically through Helm.

Disabling an enabled component or destroying Terraform pipeline definitions does **not** uninstall its release. Retire before removing its declaration. If the cleanup pipeline was removed prematurely, reapply the same stable identity in `retire` mode to restore it. Do not destroy the project/repositories before running needed uninstall pipelines. An old platform bucket from earlier test deployments should be retained outside the new pipeline-artifact lifecycle rather than destroyed to change transport.

## Model placement and storage boundaries

Discovery packs complete single-node replicas into already allocated hosts. TP=4 on an eight-GPU host recommends two fixed replicas. Multi-node PP uses complete host groups; spare-rank packing across groups is not inferred. These are estimates, with no GPU runtime, throughput or latency validation. Multiple replicas require a model-layer routing adapter; cache-aware routing is not conversation-history persistence.

Optional model staging requires a pinned file manifest, tested image digest, confirmed existing CPU placement and enhanced OKE workload identity. The bucket retains model data; the download pipeline runs the payload transfer inside a CPU Kubernetes Job with bounded scratch space. It never downloads checkpoint payloads to the DevOps runner. See [model storage](model-storage.md). The later model stack must still materialize and verify a checkpoint in local disk/PVC storage, then start vLLM. Object Storage is not implicitly a normal checkpoint directory.

## Validation limits

Terraform tests mock OCI. Script integration tests mock external services. Opt-in chart tests render the actual upstream releases using the module's values. CPU-only live validation does not establish GPU driver/CUDA, RDMA/NCCL, model placement, KV transfer, autoscaling thresholds or serving performance. The older combined model template is not the new separate model lifecycle and is not published by infrastructure discovery.

Primary references: [OCI native Helm stages](https://docs.oracle.com/en-us/iaas/Content/devops/using/deploy-helmchart.htm), [Helm artifacts and version parameters](https://docs.oracle.com/en-us/iaas/Content/devops/using/add-helmchart.htm), [Shell command specifications](https://docs.oracle.com/en-us/iaas/Content/devops/using/command_spec.htm), [Helm CRD lifecycle](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/).

OKE authorization reference: [IAM and Kubernetes RBAC](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengaboutaccesscontrol.htm), [canonical clusters permissions and variables](https://docs.oracle.com/en-us/iaas/Content/Identity/policyreference/contengpolicyreference.htm).

## Private DevOps connectivity

`PRIVATE_ENDPOINT_CHANNEL` configures a DevOps private endpoint whose VNIC resources are created in the selected subnet. This stack uses it on the native OKE deployment environment for Helm stages. `SERVICE_VNIC_CHANNEL` accesses private resources using a service-managed VNIC; this stack uses it on Shell execution containers. Both take a subnet and optional NSGs, and both rely on routing and security rules. Neither configures RDMA or the GPUs' data path.

Oracle exposes both variants through the common `NetworkChannel` API. Provider schema acceptance alone therefore does not establish that a particular use works. The Frankfurt OKE environment became ACTIVE after using the private-endpoint configuration; Shell reuse validation separately reached the API through its service-VNIC path. This is the tested combination here.

Sources: [PrivateEndpointChannel](https://docs.oracle.com/en-us/iaas/tools/python/latest/api/devops/models/oci.devops.models.PrivateEndpointChannel.html), [ServiceVnicChannel](https://docs.oracle.com/en-us/iaas/tools/python/latest/api/devops/models/oci.devops.models.ServiceVnicChannel.html), [reference OKE environment](https://github.com/streamnsight/oke-langfuse/blob/main/modules/devops/environment/environment.tf).
