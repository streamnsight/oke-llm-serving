<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Discovery-driven node pools and component delivery

Status: implementation in progress; discovery-policy defaults confirmed. This supersedes the LWS-only bootstrap scope. GPU allocation remains disabled for development validation. Existing staged AGENTS.md belongs to the user and remains excluded from commits.

## Required outcome

Discovery produces a selected, provenance-bearing deployment capability plan: GPU host layout/quantity, transport, required shared components, dependency graph, CPU/storage estimates, editable settings and unresolved requirements. The infrastructure publisher translates that plan into matching schema.yaml and Terraform declaration defaults. Its embedded template/module files are the implementation, not a separate live-only patch.

The infrastructure stack binds an existing OKE cluster, creates or attaches the retained GPU allocation and one cluster-owned component DevOps project, and creates delivery/retirement pipelines only for needed managed capabilities. Reused capabilities get validation without installation or ownership transfer. Model-specific serving/cache/route/scaling instances retain the separate model lifecycle agreed earlier.

## Confirmed discovery policies

1. Monitoring is enabled by default; autoscaling is opt-in. Fixed serving replicas use complete spare GPU groups within already required hosts, independently of autoscaling. For example, a single-node TP=4 layout on an eight-GPU host defaults to two replicas if its estimated memory and placement requirements fit. Multinode replicas require complete host groups; no extra hosts are acquired merely to fill spare GPUs. More replicas target aggregate throughput/concurrency, with no claim of lower individual-request latency. Multiple replicas require a serving router; cache-aware routing is a separate model-layer capability and remains explicit until its adapter is validated. Workload autoscaling stays within retained allocation; no automatic GPU host scale-down.
2. Object Storage remains the discovery RMS ZIP/PAR transport. Pipeline scripts, values, manifests, desired specifications and execution results belong in Generic Artifact Registry; mirrored Helm charts belong in OCIR. Model weights are data with a separate, retained storage lifecycle: direct pinned Hugging Face download needs no staging bucket; optional Object Storage staging gets its own download/verification pipeline and manifest. Engines still need a local checkpoint directory or a tested storage connector. Staging must not copy checkpoint payloads through the small DevOps Shell runner filesystem.
3. VM.GPU visibility and exclusion reasons will be investigated separately; current discovery must retain capacity/entitlement and layout rejection diagnostics rather than assume bare metal is required.

## Architecture decisions

### Capability and ownership contract

Each requirement records its reason, supported configuration adapter, dependencies, source/chart version and digest, resource estimates, lifecycle mode and validation status. Component modes are managed, reuse and retire; absent/never-needed components create no pipelines. Discovery for another model cannot remove capabilities used by existing models.

Managed components get independent deploy/update and explicit undeploy pipelines. Reuse mode does not create a native Helm mutation stage. Retirement keeps the undeploy path available until ownership/dependency checks and removal finish; merely disabling a formerly installed component must not orphan it or silently uninstall it. Shared controllers/project have one cluster-wide owner, independent of pool/model identities.

Unknown companion commands or unsupported recipe structures remain visible as requires-validation diagnostics. They must not be silently dropped or executed as shell text. Model runtime flags such as tool parsers, prefix caching, multimodal processing and MTP do not automatically imply extra cluster operators.

### Native OCI DevOps stages

Charts are mirrored from their verified upstream source into OCIR by an import stage. Native OKE_HELM_CHART_DEPLOYMENT stages perform Helm installs/upgrades using a private OKE deployment environment. Generic Artifact Registry supplies parameterized values files, scripts and raw manifests. Source artifacts and execution reports have immutable versions and exact references.

Use common editable DevOps pipeline parameters: Shell stages explicitly export them as environment variables; native Helm stages consume them through values, release/namespace and artifact-version parameters. Helm stages do not expose a general Shell environment. A chart-version override must import/resolve that exact version before deployment. Support OCI's ENFORCE_HELM_DEPLOYMENT override for intentional reapplication.

Shell stages are for import/promotion, explicit CRD lifecycle work, inventory/preflight/validation and unavoidable teardown. OCI's Helm-command purpose supports read commands, not uninstall, so explicit undeploy uses a narrowly scoped Shell helm-uninstall command. Set is_uninstall_on_stage_delete=false to avoid deleting shared releases when pipeline definitions change.

Helm chart CRDs under crds/ need explicit upgrade handling and survive normal uninstall. Inspect actual chart resources; template-rendered CRDs and PVCs may have different lifecycles. Ordinary retirement preserves CRDs/persistent data, never removes foreign releases/OKE add-ons, and checks dependent workloads. Data/CRD purging is a separate explicit operation.

### Parallel execution and evidence

Independent components can deploy concurrently; each directly invoked pipeline checks its own prerequisites. A coordination pipeline expresses dependency edges and invokes/awaits independent component pipelines. The final validator checks the current cluster and exact required component revisions.

Use per-component generations and append-only execution reports rather than one shared mutable readiness object. Concurrent operations on the same release need an atomic Kubernetes Lease or verified service serialization, with a unique execution identity, bounded native-stage duration and explicit recovery checks. A list-running-then-start check is not a lock. Changing unrelated cluster/add-on status must not change a component generation or replace storage.

### Allocation and network lifecycle

Transport defaults follow the selected execution/transfer topology plus shape, region, OKE/image and add-on capabilities. A single host may need only its intra-node interconnect. Hardware RDMA capability alone must not force Compute Cluster allocation. Fabric/capacity observations are not reservations or runtime NCCL/NIXL proof.

Keep image, Kubernetes version, shape, AD, subnets, Compute Cluster and transport stable for an allocated pool; component updates must not trigger GPU node cycling or replacement. Changing those bindings belongs to explicit pool maintenance. Fix the allocation module's Compute Cluster IAM writes to use the home-region provider before RDMA execution. Existing CPU pools host shared workloads; this stack creates no CPU pool.

Native Workload/PodGroup gang scheduling requires actual served APIs and control-plane support, not just Kubernetes 1.37. Do not install native APIs as CRDs. Reuse OKE-managed GPU/network/telemetry capabilities before adding standalone components.

## Capability families

| Selected configuration | Shared capability | Model-layer configuration |
| --- | --- | --- |
| Single GPU or intra-node TP/PP | GPU resources; monitoring policy | Deployment/StatefulSet, image, runtime flags and services |
| Multi-node multiprocessing | LWS and compatible transport | LWS instance, rendezvous, head/worker commands and sizing |
| Ray executor | KubeRay only when selected | RayCluster/RayService and serving configuration |
| Native prefix cache/offload | Storage prerequisites when needed | Engine options and bounded offload resources |
| LMCache | Placement/IPC/storage prerequisites; no assumed universal operator | Typed connector/server adapter, compatible image, ports and memory budget |
| Prefill/decode | LWS/DAS or an explicitly selected integration; gateway/connector prerequisites | Role-specific groups, transfer, routing and readiness |
| MoE/expert parallelism | Selected communication/executor prerequisites | EP/DP/TP and backend configuration |
| Monitoring | Reuse or manage Prometheus/operator/exporters | Scrape resources, rules and dashboards |
| Request-aware scaling | KEDA and accessible metrics endpoint | ScaledObject, workload/role target and measured thresholds |
| Admission/gang policy | Selected verified Kueue/native/scheduler integration | Queues, resource flavors and group policy |
| Inference routing | Selected gateway/controller/API dependencies | InferencePool/routes/EPP or serving router |
| Model distribution | Optional retained model-data bucket, access policy and CPU download job | Pinned source/revision manifest, staged object download to local disk/PVC and cache placement |

LWS 1.0.0 supports DisaggregatedSet when enabled; this must become a selected chart capability, with CRD upgrades handled explicitly. Recipe examples are not a CPU-memory sizing policy: an illustrative LMCache 512-GiB pool cannot be copied into every OCI host recommendation. Third-party serving platforms are separate adapters with their own dependencies, not implicit consequences of choosing vLLM.

## Phases and tasks

1. [x] Audit current discovery, native OCI Helm stages, artifact delivery, ownership and teardown in parallel.
2. [x] Freeze capability/ownership/lifecycle contracts and policy defaults. Add tests for dependency closure, disabled/reused modes and unknown recipe requirements.
3. [ ] Extend discovery beyond hardcoded single_node_tp: preserve complete recipe selections/companions, derive supported topology/transport and component needs, estimate enabled CPU/storage budgets, and generate editable schema/HCL defaults.
4. [x] Build the shared delivery foundation: OKE deploy environment, OCIR chart import, Artifact Registry source/results, parameter mapping, per-component identity/evidence and locking, and conditional pipeline resources. Refactor LWS to native Helm with explicit CRD/retire stages.
5. [ ] Develop component adapters in parallel after the common contract is fixed: monitoring/metrics, KEDA, LWS/DAS/network and selected additional controller/gateway integrations. Reuse compatible existing installations; make unsupported integrations explicit.
   - [ ] Add optional model storage/download adapter; verify immutable revision, authentication, resumability, manifest publication, storage limits and data-preserving teardown. GPU-local warmup and serving integration remain model-stack responsibilities.
6. [x] Integrate the deployment dependency graph, fresh aggregate validation, existing-platform/pool reuse and safe reverse-order retirement. Keep the teardown path until successful retirement, and preserve shared dependents/data. CPU graph/reuse and guarded KEDA uninstall/reinstall passed live; retained-pool behavior remains locally tested without allocating GPUs.
7. [x] Protect retained pool bindings and correct home-region Compute Cluster IAM. Test component changes produce no GPU allocation changes; inspect RDMA eligibility and fallback diagnostics without allocating GPUs.
8. [ ] Verify charts/CRDs, native Terraform, concurrency/failure/retry/retirement cases and repository-to-ZIP parity. Run CPU-only RMS deploy/update/reuse/retire and synthetic Prometheus/KEDA tests; document GPU/RDMA validation still outstanding.
9. [ ] Commit feature slices, integrate after validation, rebuild discovery and configured child packages, document exactly which live stack sources/ZIPs/PARs were updated, and clean temporary assets.

## Validation requirements

- No pipelines for absent, never-needed components; required dependency closure remains complete.
- Reused releases are never adopted/upgraded/uninstalled; a Helm preflight cannot merely succeed and then mutate a foreign release.
- Editing per-run settings changes actual Helm values/Shell configuration and records its effective hash.
- Independent components run concurrently; competing operations on the same component serialize, including interrupted runs.
- Disabling an installed component cannot lose its retirement path; dependent models/scalers/scrape targets block unsafe removal.
- CRDs, namespaces, retained data, GPU pools and foreign add-ons survive ordinary component retirement.
- Prometheus/KEDA work with synthetic CPU workloads while GPU allocation is skipped; GPU/DCGM/fabric assertions stay unvalidated until real devices exist.
- Generated defaults, publisher dependency closure and packaged source match repository source. No production claim comes from mocked checks alone.

## Implemented slices

- Discovery packs complete intra-host replicas into allocated hosts, preserves complete recipe companion evidence and emits topology/component/routing/storage diagnostics. PP groups remain complete; the live recipe request still uses the supported single-node adapter. Additional P/D/Ray/gateway adapters are not implied by installing LWS.
- Infrastructure defaults enable monitoring, opt into KEDA only when selected, and enable LWS/DAS by topology. Publisher embeds matching editable schema and HCL defaults plus the new module closure.
- Independent managed/reuse/retire component delivery uses OCIR/native Helm, Generic Artifact inputs/results, bounded atomic release leases, owned raw CRD updates, retained templated CRDs and explicit dependency-guarded uninstall. Coordinator and fresh validator run separately; Terraform does not declare runtime readiness.
- Optional retained model storage and CPU Job staging are implemented with pinned manifests, workload identity, resumability/checksums and separate data lifecycle. Its image build, live storage/identity checks and later GPU-local model warmup remain pending.
- Retained allocation bindings are guarded against image/version/network changes, and Compute Cluster IAM uses the home provider. No GPU allocation/cycling is authorized for current validation.
- CPU-only live RMS Apply and the full parallel component graph succeeded with allocation disabled. Corrected component/aggregate metadata checks passed live, including Prometheus PVC and KEDA API aggregation. Guarded KEDA uninstall retained all six CRDs; reinstall succeeded. Historical Object Storage evidence was retained. Packages validated with RMS Terraform 1.5.7. Integration into main remains pending the remaining feature validation.
- OKE add-on preflight blocks known missing/inactive GPU support and the managed pod-RDMA prerequisite before retained allocation. Basic/manual integrations remain unverified. Automatic add-on management and GPU exporter/scrape configuration remain unfinished; ACTIVE add-ons do not establish device/CUDA/fabric readiness.

## Primary references

- [OCI Helm deployment](https://docs.oracle.com/en-us/iaas/Content/devops/using/deploy-helmchart.htm), [chart sources](https://docs.oracle.com/en-us/iaas/Content/devops/using/add-helmchart.htm), [private OKE environment](https://docs.oracle.com/en-us/iaas/Content/devops/using/create_oke_environment.htm), [supported Helm commands](https://docs.oracle.com/en-us/iaas/Content/devops/using/add-helmspecs.htm).
- [oke-langfuse chart mirroring](https://github.com/streamnsight/oke-langfuse/blob/main/modules/devops/ocir/push_helm_chart/push_helm_chart.tf) and [native Helm stages](https://github.com/streamnsight/oke-langfuse/blob/main/modules/apps/langfuse/helm_chart/devops_pipeline.tf).
- [LWS installation and scheduling gates](https://lws.sigs.k8s.io/stable/docs/installation/), [Helm CRD lifecycle](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/), [OKE managed add-ons](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengintroducingclusteraddons.htm).
- [vLLM parallelism](https://docs.vllm.ai/en/stable/serving/parallelism_scaling/), [LMCache multiprocess deployment](https://docs.lmcache.ai/mp/deployment.html), [KEDA Prometheus scaler](https://keda.sh/docs/2.20/scalers/prometheus/), [Kueue LWS integration](https://kueue.sigs.k8s.io/docs/tasks/run/leaderworkerset/).
