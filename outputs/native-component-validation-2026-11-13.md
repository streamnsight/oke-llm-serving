<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Discovery-driven components: implementation and validation

Work date: November 13, 2026, America/Los_Angeles. OCI execution timestamps below use UTC on November 14. Feature branch: `feat/discovery-driven-platform-components`. This report supersedes the earlier LWS-only bootstrap description for the new implementation; it does not claim GPU serving validation.

## Implemented behavior

Discovery defaults monitoring on and workload autoscaling off. Single-node layouts pack complete replicas into already required GPU hosts. A TP=4 replica on an eight-GPU host recommends two fixed replicas; a minimum of three requires two hosts and can fill four replica slots. Both capacity and entitlement must cover the complete host allocation. PP replicas retain complete host groups; spare-rank packing across PP groups is not inferred.

For opt-in autoscaling, the requested minimum is the lower bound and complete replica capacity inside the retained allocation is the upper bound. Initial replicas use the minimum. Configurations with no growth headroom report that explicitly; a larger allocation needs another quantity-specific capacity check. GPU hosts are not automatically scaled down. Context/concurrency memory assumptions are per replica, not measured aggregate throughput.

Each option carries topology, required components, routing needs, recipe selections/companions, budgets and unresolved diagnostics. Unknown companion commands remain inert evidence. Multiple replicas require model-layer routing; cache-aware routing is separate from persistent conversation history.

The infrastructure publisher embeds editable matching Terraform declaration and RMS schema defaults for hardware, transport, LWS/DAS, monitoring, scaling and model-storage mode. Its dependency closure includes component delivery and optional model storage. No large JSON variable or tfvars file overrides the form.

## Delivery and ownership

- Managed components: Shell prepare/import → native OCI Helm → Shell validation; separate guarded undeploy pipeline.
- Reuse: validation only, no ownership adoption or native install stage.
- Retire: preserve the explicit undeploy path until it is run. Removing Terraform pipeline definitions does not uninstall workloads.
- Scripts, values, specifications, command files and immutable execution reports use Generic Artifact Registry. Charts use private OCIR repositories.
- Managed release operations use an atomic Kubernetes Lease and stable ownership identity. Raw CRDs require matching ownership for updates; no forced field takeover. Templated CRDs/PVCs require Helm retention annotations. Uninstall checks external consumers and preserves namespaces, CRDs, persistent data and GPU allocation.
- Native Helm stages use `PRIVATE_ENDPOINT_CHANNEL` on the OKE environment; Shell containers use `SERVICE_VNIC_CHANNEL`. Both need private connectivity, independent of OBC.
- Default Kubernetes authorization grants only `CLUSTER_MANAGE`, constrained to the selected cluster and exact pipeline principals. OCI cluster update/delete and node-pool management are excluded. Explicit RBAC mode remains available.

The shared adapters currently cover Prometheus/operator, KEDA, LWS and the LWS DisaggregatedSet feature. Additional Ray, admission/gang, routing and disaggregated recipe integrations remain explicit follow-up adapters rather than assumed capabilities.

OKE's GPU and Network Operator add-ons are optional, not a consequence of selecting an enhanced cluster. Allocation preflight now blocks known missing/inactive native GPU support on enhanced clusters; the managed pod-RDMA path also requires an ACTIVE Network Operator before either the retained Compute Cluster or GPU pool is created. An explicitly disabled GPU Operator device plugin requires another active plugin. Basic-cluster/manual integrations remain unverified. Evidence is published in `allocation.addon_prerequisites`. This does not enable missing add-ons or configure GPU exporter scraping. Compute Cluster placement automatically configures the host's Oracle Cloud Agent RDMA plugins, which does not establish RDMA devices inside Kubernetes pods. GPU metrics, pod fabric configuration and automatic add-on management remain explicit prerequisites/follow-up work. Sources: [OKE add-ons](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengintroducingclusteraddons.htm), [Compute Cluster pools](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengusingcomputeclusters.htm), [GPU Operator settings](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/configuration-arguments-nvidia-gpu-operator.htm).

## Model distribution

Direct pinned Hugging Face download is the default and creates no staging resources. Optional Object Storage mode creates a retained private versioned model-data bucket and independent CPU download-job pipeline. Software artifacts do not share that bucket. The adapter provides pinned revisions/file allowlists, resumable transfers, checksums, completion manifests, Vault-token handling and service-account workload identity.

The staging image still requires building and live validation. The allowlist is not proof that every multimodal or external-config asset is present. Model-stack consumption, GPU-local/PVC warmup and shared storage reuse across later model deployments remain pending. No model weights were downloaded during this validation.

## Local verification

Relevant Terraform suites passed: discovery root (9), planner (42), GPU allocation (23), platform bootstrap (9), component delivery (1), model storage (6), model profile (11), infrastructure publisher (10), target discovery (10), infrastructure template (11), older combined template (22), and handoff (2). These mock OCI; they are not evidence of cloud execution. The full JavaScript/Bash/chart run passed 67 tests with two optional older-chart checks skipped before the final metadata regression fix.

Script tests run actual Bash/jq with simulated external interfaces. Component delivery includes strict OCIR response-envelope parsing, token-file cleanup, failed evidence uploads, ownership, CRD updates, locking, retirement and external-consumer guards. Model-storage tests include Pending WaitForFirstConsumer PVCs, size/checksum failures, resumption, identity/token handling and execution-specific cleanup.

Actual published charts rendered successfully using the module's own values: LWS 1.0.0, kube-prometheus-stack 93.3.0, and KEDA 2.21.0. Checks cover CPU placement, deployment/CRD names, KEDA's six templated CRDs with keep annotations, DAS webhooks, Prometheus retention/PVC configuration and KEDA API aggregation resources.

The entry ZIP and configured child ZIP passed extraction, relocated module resolution and Terraform validation. Archive generation was also tested with a saved Plan transferred to a fresh Apply directory. All three roots validate with RMS's Terraform 1.5.7.

## Live OCI execution

The existing Frankfurt RMS stack was updated with GPU allocation disabled throughout. Before each Apply, the saved JSON Plan was inspected programmatically to reject GPU/node-pool/Compute Cluster/capacity-reservation or bucket changes. No GPU hosts or CPU node pools were allocated, resized, cycled or deleted by this work.

The old private versioned platform evidence bucket and its historical specification object were retained. Only their obsolete Terraform ownership was removed using a backed-up state import; the actual cloud resources remain intact. New reports use Artifact Registry. Source/state backups, safety summaries and full private execution evidence are under ignored `work/platform-components/`.

The corrected infrastructure Apply succeeded with an ACTIVE private OKE environment, two OCIR chart repositories, separate source/result artifact repositories and seven pipelines: deploy graph, fresh validation, LWS reuse, Prometheus deploy/undeploy, and KEDA deploy/undeploy. The live debug configuration explicitly reuses existing LWS and opts into KEDA; ordinary single-node discovery defaults do not create an unnecessary LWS or KEDA pipeline.

The LWS reuse execution succeeded at `2026-11-14T03:44:40.951Z`. It fetched checksum-verified Generic Artifact inputs, reached the private Kubernetes API through the service-VNIC runner, checked all three LWS/DAS CRDs and verified controller rollout. Its immutable reuse report is present in the result repository. The local OBC tunnel was unavailable during these checks; the user is investigating it separately.

Service issues caught by live execution and fixed in source:

1. A stage-only `OCI_DEVOPS_DEPLOY_USE_CREATE_NAMESPACE_FLAG` was rejected as a pipeline parameter. Removed; prepare already creates the namespace.
2. The native environment initially used the Shell channel configuration. The corrected private-endpoint configuration became ACTIVE.
3. An empty optional recovery default was treated as a required launch argument. It now defaults to `none`.
4. `oci raw-request` returned a response envelope that was mistakenly used as an OCIR credential. The helper now checks HTTP status, extracts only the token and supplies a private Helm registry-token config. Read-only verification with Helm 3.19.2 reached the empty private mirror and correctly reported the absent tag. Failed prepare runs had not reached native installation and released their locks.
5. Both managed chart installations then succeeded, including controller/CRD checks, but the verifier expected chart metadata in `helm status`. Helm deliberately removes that metadata. Component and aggregate validation now use `helm get metadata`, check matching release revisions and retain the exact chart/version and effective-values checks. The mock interface was corrected to reproduce Helm's real output. See [Helm status implementation](https://github.com/helm/helm/blob/v3.19.2/cmd/helm/status.go) and [metadata implementation](https://github.com/helm/helm/blob/v3.19.2/cmd/helm/get_metadata.go). The final component suite passed 13 tests and the platform suite passed 12 tests.

Prometheus and KEDA native chart installation succeeded. The corrected metadata verifier was committed as `888f58e` and deployed by a successful RMS Apply after a saved-Plan guard permitted only 26 artifact changes. The resulting state has 60 managed OCI resource instances, zero managed allocation resources and GPU allocation disabled.

The guarded KEDA undeploy pipeline succeeded. Its execution log confirms that Helm retained all six KEDA CRDs and uninstalled the owned release. The coordinator then launched LWS reuse, Prometheus and KEDA concurrently. All three succeeded, and the coordinator completed fresh aggregate validation successfully at `2026-11-14T05:06:23.037Z`. Component reports show Prometheus ready at Helm revision 2 and reinstalled KEDA ready at revision 1. Aggregate checks include Prometheus StatefulSet/PVC readiness, KEDA APIService availability and current managed generations/revisions, using the private API from the VCN runner.

This completes the tested CPU component deployment/reuse/retirement/reinstall flow. It does not include a synthetic scaling load test or prove GPU readiness. GPU drivers/CUDA, RDMA/NCCL, GPU exporter scraping, serving replicas, LMCache/KV transfer, model routing and workload performance remain unvalidated. The add-on preflight (`1fb0e57`) has 23 local Terraform test passes; its allocation path was not exercised live because GPU allocation remains disabled.

## Publication and next steps

Repository changes are committed on the feature branch; integration into main awaits the remaining feature validation. The root `make package` rebuilds the discovery entry ZIP with both downstream templates and all module assets. Its final code validated with Terraform 1.5.7. The tested RMS infrastructure runtime source is `888f58e`; subsequent GPU preflight changes are included in the local packages and have local test coverage, but were not used to allocate GPUs. Rebuilding local packages does not rewrite previously published ZIP objects/PARs or update a separate live discovery stack. Those require discovery with the rebuilt source.

Next: automatic OKE add-on configuration and GPU exporter/scrape integration; staging image and live model-data checks; then the separate model layer with actual serving replicas, routing/cache instances, workload metrics/scalers, validation and vLLM benchmarking. Additional topology adapters remain explicit work. Keep GPU allocation disabled until an explicit reviewed allocation is selected. Development node_modules, generated test archives and untracked module lockfiles were removed; private evidence/state backups were retained.
