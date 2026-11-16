<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Independent model projects and retained platform access

Discovery publishes infrastructure and model ZIPs for every confirmed option. Both links exist before infrastructure Apply. The model ZIP contains `inputs/model-spec.json`, model/runtime modules and matching editable schema/HCL defaults. It has no completed-platform binding file and never runs nested Terraform.

The model specification freezes the model/revision, structured Hub profile, context/concurrency, selected GPU layout and exact serving recipe evidence. A model stack creates a new DevOps project, private OKE deployment environment, source/results artifact repositories, OCIR chart repository, scoped IAM and four deploy/validate/benchmark/undeploy pipelines. It owns none of the GPU hosts, Compute Clusters or shared controllers.

## Cluster ID as the required input

Select an existing cluster in the option's region. Native OCI lookups infer its VCN, runner subnet/NSGs, Kubernetes version and compatible managed GPU pool. Matching considers shape and managed allocation ownership/labels. A unique pool in the discovery AD is preferred; a unique compatible retained pool elsewhere in the cluster's region can be reused. Actual placement is recorded. Discovery's AD constrains a new allocation, not reuse of hosts already retained.

Apply requires an existing compatible managed GPU pool and the platform's trusted model-onboarding pipeline. Complete the infrastructure/components stack first. The cluster-only form still discovers the allocation automatically; no component-project or pipeline OCID is required. Multiple matching pools, duplicate trusted pipelines or incompatible network policies fail with an explicit issue rather than selecting arbitrarily. Optional pool/platform/network overrides live under advanced settings. These are read-only lookups: the model stack never creates, resizes, cycles or deletes nodes.

Shared component installation is configured in infrastructure. In the model stack, optional model monitoring resources, autoscaling policy and weight delivery are editable deployment settings. Disabling model monitoring removes the inherited Prometheus/GPU-telemetry requirements; enabling autoscaling still requires retained Prometheus and KEDA. Discovery recommendations supply defaults and do not freeze these optional choices.

Shared CPU controllers can serve multiple model projects. Model replicas, routes, caches and task-specific companions have model lifecycle. Recipe companion flags alone do not install the required services; unsupported adapters fail explicitly.

## Runtime readiness and namespace onboarding

Model stack Apply discovers the trusted onboarding pipeline and runs it with exact model project/pipeline identities, namespace and actual GPU pool. After onboarding succeeds, Apply runs model deployment and then the independent validation pipeline, waiting for each to succeed. A failure fails Apply; benchmarking remains a separate manual operation. An unchanged Apply reuses completed executions. The reported `onboarding_arguments` remain available for explicit manual grant/revoke operations.

The trusted script checks the active project and each exact active pipeline's fixed project, cluster, platform, pool and namespace defaults before granting access. It creates only code-defined namespace RBAC/service-account resources. Existing namespaces must match platform ownership **and the exact model project ID**. Another project cannot claim retained data by reusing a namespace name. Concurrent changes use a namespace lease; orphaned locks require explicit inspection/recovery.

The lookup checks the exact active platform project, onboarding stage and raw inline command-spec binding to the selected cluster/platform/project. Missing or mismatched prerequisites stop model Apply before workload deployment. The model stack uses the existing trusted operation and does not change shared component definitions.

Model principals receive namespace-scoped workload/Helm/PVC permissions, read-only nodes/API/CRDs, and exact-name read access to trusted controller/ownership context. The immutable platform context is stored under `kube-system`; shared-controller reads are separately scoped. Model principals cannot install shared controllers, write nodes, bind/escalate cluster roles or read arbitrary cluster-wide Pod specifications. Cross-compartment projects require an operator to grant the trusted onboarding principal read access to DevOps metadata in that project compartment; no tenancy-wide access is added automatically.

At execution, preflight resolves the live managed pool and binds its OCI instances to actual Kubernetes Ready GPU nodes, shape, ownership and transport. Required controllers are checked against current trusted ownership/generation and rollout evidence. RDMA requires the real Compute Cluster/AD/device setup; it is never assumed from the shape name alone.

Pool allocatable GPU capacity is **not free capacity**. Other namespaces' Pod specs are not exposed for occupancy calculation. Free headroom remains unknown at preflight; Kubernetes GPU resource requests and bounded rollout/readiness establish whether scheduling succeeds. Upgrades use no-surge rollout and model-scoped locks.

## Storage, validation and teardown

Direct Hub downloads require enough workspace for the full pinned snapshot per engine Pod. Packed replicas do not automatically share a cache. Object Storage staging, when explicitly configured, belongs to the model project; it requires a compatible CPU staging image and verified serving-volume materialization. The stager's RWO scratch PVC is not a shared GPU model volume. Unsupported staged materialization blocks deployment rather than silently switching sources.

Native Helm deploys the model-owned workload chart and optional prefix-aware Production Stack router. Apply also runs the separate API/readiness validation pipeline. Official vLLM benchmarking and guarded retirement remain manual pipelines. Benchmark/API adapters are task-specific; health/model-list checks do not validate every modality. Successful Apply establishes the configured readiness and API checks; cache behavior, fabric performance and throughput still require hardware benchmarks.

Retire the model release first, revoke its namespace access through trusted onboarding, then destroy model Terraform metadata. Pipeline destruction alone does not uninstall a previously executed Helm release. Revoke can use persisted owned identity records after metadata deletion, but cleanup before deleting metadata is easier to inspect. Active Pods block revocation. Namespaces, retained PVCs/model data, shared controllers and GPU hosts are preserved.

Recreating a destroyed model project produces a different project identity. It cannot silently adopt its predecessor's retained namespace. Use another model namespace/name or an explicit administrator recovery after retirement/revocation. Automatic namespace/data purge and cross-project ownership transfer are not implemented.

File-backed software and downloadable benchmark results use Generic Artifacts; charts use OCIR. Routine deployment, validation and failure summaries go to DevOps logs. Only discovery bundles/reports and explicitly selected retained model data use Object Storage. Configured ZIPs have root-level `main.tf`, with run identity in the ZIP filename under `models/<owner--model>/<region>/<shape>/`; bounded classic Object Storage PARs are used for RMS launch URLs.

Independent projects establish resource ownership and teardown boundaries. They do not establish complete OCI artifact isolation: the current runner policies grant Generic Artifact access at compartment scope. Put projects with different trust requirements in separate compartments with explicitly reviewed policies. Kubernetes namespace authorization remains separate from that artifact policy.
