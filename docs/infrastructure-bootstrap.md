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
| KEDA and external metrics API | On as a shared capability | Independent native Helm; each model opts into its own ScaledObject later |
| LWS / DisaggregatedSet | Required by selected topology | Independent native Helm plus explicit owned raw-CRD preparation |
| OKE hardware add-ons | Enable missing, reuse existing | NFD, NVIDIA GPU integration, Network Operator for RDMA, compatible bare-metal health controller. Existing settings and shared add-ons are retained; failed configurations stop allocation |
| Router, LMCache instances, serving replicas and ScaledObjects | Model layer | Not installed by infrastructure bootstrap |
| Optional model-data staging | Direct Hub download by default | Separate retained bucket and CPU download Job pipeline when configured |

Prometheus and KEDA controllers can install concurrently: KEDA installation does not require a live Prometheus endpoint. A model's later scaling configuration must validate that endpoint and its query. KEDA queries Prometheus directly; this does not require a separate Prometheus Adapter. Node autoscaling is not enabled.

OKE's GPU/network add-ons are optional. Infrastructure Apply [enables missing native add-ons](oke-managed-addons.md) on an enhanced cluster before the allocation preflight publishes `allocation.addon_prerequisites`. Existing add-on versions/settings are preserved and failed installations need explicit repair. An ACTIVE Network Operator does not prove pod RDMA devices are configured; GPU health policy and metric exporter/scrape configuration remain separate. Compute Cluster placement configures host RDMA agents separately. Runtime checks must still verify advertised devices, CUDA and fabric operation.

Images and bundled dependencies come from each Helm chart. Module-local chart versions freeze the platform recommendation; the recipe-selected vLLM image is a separate runtime decision. Chart mirroring and the native stage share the editable `CHART_VERSION` argument. Updating component charts is an explicit deployment operation, not an automatic consequence of looking up a newer model recipe.

## Run the pipelines

1. Review Terraform Plan, then Apply. This enables missing native OKE hardware add-ons and creates DevOps pipelines. It then starts the component coordinator and waits for successful deployment and readiness validation. A failed child run fails Apply.
2. The default `cluster_authorization_mode=iam` grants pipeline principals Kubernetes administration through `CLUSTER_MANAGE`, scoped to this exact cluster. It grants no OCI cluster update/delete or node-pool permissions. For explicit Kubernetes RBAC instead, select `rbac` and arrange the generated `bootstrap_rbac` binding as cluster administrator before execution. Automatic execution will fail until those principals are authorized; existing metadata can then be used to install the binding and retry. Both stage types also need private API connectivity; the stack supplies a private OKE environment and a separate private Shell runner channel.
3. Inspect `platform.automatic_deployment` for the coordinator execution ID, terminal state and revision. First Apply and meaningful component/code/binding changes start a run; unchanged Applies do not. Independent components start concurrently and dependencies remain explicit. Use `platform.bootstrap_pipeline_id` or an individual `component_pipeline_ids` entry for a later manual run, with editable non-secret parameters. Do not overlap a coordinator with manual updates of the same release.
4. Run `platform.validation_pipeline_id` for fresh, read-only checks. It verifies current releases, managed ownership/generation markers, controller rollouts, Prometheus StatefulSet/PVC readiness and KEDA API aggregation when selected. GPU debug mode records its reduced scope and does not wait for GPUs.
5. Read the structured operation and readiness summaries in the project's DevOps logs (`platform.evidence`). They include execution identity and status without a separate report-upload dependency. There is no shared mutable `latest` readiness marker.

Small scripts and specifications are readable inline command specs, materialized with quoted heredocs and verified by exact checksums. Helm values use inline Generic File artifacts; chart/runtime assets that need file delivery remain in Generic Artifact Registry. Inline payloads check raw UTF-8 bytes against 51,200 and pass plaintext to the OCI Terraform provider; the Go SDK handles base64 transport encoding. Charts are mirrored into private OCIR repositories for native `OKE_HELM_CHART_DEPLOYMENT` stages. No models or new readiness reports are stored in a platform artifact bucket. Object Storage remains the discovery ZIP/PAR transport and optional model-data storage.

The code uses readable Shell files and explicit environment exports. Native chart values use `${PARAMETER}` placeholders. `COMMAND_SPEC` artifacts use substitution mode `NONE`; Shell resolves its environment bindings. Neither scripts nor configuration are decoded from a base64 payload inside a command. Only the OCI artifact API transport uses its required base64 field; the decoded YAML/Bash stays readable.

## Ownership, upgrades and teardown

Set component lifecycle modes to `managed`, `reuse` or `retire`. Reuse creates validation only, with no mutating native stage, ownership adoption or uninstall pipeline. Managed delivery refuses an existing foreign release or raw CRD. Resolve ownership explicitly instead of automatically adopting shared resources.

Managed operations acquire an atomic Kubernetes Lease for the cluster/namespace/release and keep it across the native Helm stage. Other components can run concurrently. Failed or interrupted native stages deliberately retain that lease. Explicit recovery requires the old deployment OCID, its terminal OCI status and lease expiry; expiry alone never grants takeover. See [component delivery](../modules/shared/component-delivery/README.md) for the recovery contract.

To remove a managed component, keep its declaration in `retire` mode, Apply, then run its separate `undeploy_pipeline_ids` entry. Dedicated undeploy pipelines default `CONFIRM_UNINSTALL` to `true`; selecting and running that pipeline is sufficient. Removal checks exact ownership and external dependents. Ordinary uninstall preserves namespaces, CRDs, PVCs, model data and GPU allocations. KEDA's templated CRDs have Helm keep annotations. Raw LWS/Prometheus CRDs are created/updated explicitly using server-side apply without forced field conflicts. Chart CRD upgrades are not assumed to happen automatically through Helm.

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

## Artifact repository destruction

Destroy empties the platform-owned source repository before deleting it, including historical file versions. Routine execution reports stay in DevOps Logging; no separate platform results repository is created. Cleanup runs on the Terraform/RMS host with that host's existing OCI principal/profile and requires permission to list and delete generic artifacts. A cleanup error stops repository deletion. The helper is packaged with the platform module; no Kubernetes API access is needed.

The hooks are attached directly to existing repository resources, so an updated stack source can retry a previously failed Destroy without an Apply to register another resource. Run the explicit component undeploy pipelines separately when removing releases; repository cleanup does not uninstall cluster components or change retained GPU protection.

For local mocked Terraform tests, use `bash scripts/test-terraform.sh modules/cluster-add-ons/platform-bootstrap` (and the same wrapper for `templates/infrastructure`). Terraform provider mocks still run destroy provisioners; the wrapper supplies a strict fake OCI CLI that accepts only fixture repositories and never contacts OCI. Cleanup behavior is separately tested with populated, failing and delayed fake repositories.

## Controller installation and model choices

The shared KEDA controller is installed/reused by default (`keda_enabled=true`), independently of model autoscaling. Model stacks keep `autoscaling_enabled=false` until the user opts in; only then is a model ScaledObject created and validated against existing KEDA/Prometheus. KEDA installation does not force Prometheus installation or allocate/scale GPU nodes. Use reuse for an existing compatible KEDA installation.

LWS is selected for supported multi-node replicas and for DisaggregatedSet child groups. Disaggregated prefill/decode roles can use different GPUs within the same host; they do not require multiple hosts. A single combined vLLM Pod using tensor parallelism within one host does not by itself need LWS. DisaggregatedSet stays off unless the chosen topology needs separate prefill/decode roles. Enabling it selects LWS as well. Controller availability alone does not configure KV transfer, a coordinating router, cache sharing or a working disaggregated model adapter.

For a hypothetical four-GPU node where each role fits on two GPUs, one combined TP4 replica, two combined TP2 replicas, and a TP2 prefill plus TP2 decode deployment are distinct layouts. The disaggregated layout uses a separate model copy per role, needs a compatible KV-transfer connector/router and sufficient memory for both roles, and must be benchmarked against the combined alternatives. DisaggregatedSet maps each role to a child LWS, which may contain just one Pod. The current model chart renders combined Deployment/LWS workloads; its DisaggregatedSet model adapter is still unimplemented. The infrastructure toggle prepares controllers only.

The automatic execution uses Terraform's native `oci_devops_deployment`, which waits for `SUCCEEDED` and preserves historical execution records when removed from state. It does not uninstall charts on Destroy. Failed/timed-out executions require inspecting their children and any retained lease before retrying. Exact stale-lock recovery remains explicit; expiry alone never permits takeover.

Chart mirroring requires `CHART_VERSION` to exactly match chart metadata, including a leading `v` when present. LWS uses `v1.0.0`; a prefix mismatch now fails before pushing a tag that the native Helm stage cannot fetch.
