<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Project status

Discovery now exposes exactly one RMS output: a link to a self-contained Redwood-styled HTML report in Object Storage. It contains model/checkpoint metadata, context/concurrency memory estimates and their limitations, every confirmed capacity option in a collapsed section, recipe commands/configuration, both child-stack link groups, and regional capacity/limit evidence. Zero-option assessments still produce a page. Opening/filtering the page performs no additional discovery calls.

Both configured infrastructure and model ZIPs are generated during discovery. The infrastructure stack owns retained GPU allocation and shared controllers. Each model stack creates an independent DevOps project/environment/repositories and four deploy/validate/benchmark/undeploy pipelines. The normal model form asks only for the cluster: native lookups resolve network and compatible managed GPU-pool metadata, with advanced overrides for ambiguity. Missing GPU allocation/controller readiness does not prevent metadata creation; runtime execution checks the real platform later. No completed infrastructure binding JSON is required.

Live RMS discovery publication, PAR downloads, hosted report rendering and native validation of generated ZIPs passed. The cluster-only model stack passed live RMS Plan/Apply without a GPU pool. Service API checks confirmed its independent project/environment, four ACTIVE model pipelines and six ACTIVE stages (one native Helm, five Shell). No pipeline was executed. See [the validation record](discovery-html-validation-2026-11-14.md).

The shared CPU component foundation was previously validated live: LWS reuse, parallel Prometheus/KEDA installation, fresh aggregate readiness and guarded KEDA uninstall/reinstall retaining six KEDA CRDs. See [that validation](native-component-validation-2026-11-13.md). Prometheus defaults on, KEDA is opt-in and LWS follows topology. Existing CPU pools host controllers; infrastructure creates no CPU pool. The temporary `skip_gpu_allocation` debug flag suppresses allocation only and must never be enabled after retaining GPU hosts.

Model workloads use a repository-owned native Helm chart for Deployment/LWS and an optional pinned Production Stack router dependency. Native Helm and artifact-backed Shell stages remain explicit operations. Shared components have platform lifecycle; model releases, routes/cache instances and scaling resources have model lifecycle. Scripts/configuration/evidence use Generic Artifacts, charts use OCIR; Object Storage holds discovery bundles/reports and explicitly selected retained model data.

## Remaining work and validation limits

- Update existing platform onboarding delivery to the current independent-project identity flow before onboarding new model projects. Cross-project authorization has local executable coverage; it was not run against Kubernetes in this validation. Model runners receive namespace writes and bounded shared read access, not cluster administration. Generic Artifact IAM is still compartment-scoped.
- Execute GPU allocation and actual model deploy/validate/benchmark/undeploy only when authorized. Driver/CUDA/NCCL/RDMA, scheduling, inference modalities, cache behavior and performance remain unvalidated on hardware. Free headroom across other model namespaces is unknown until scheduling/rollout succeeds.
- Finish automatic OKE GPU/network add-on configuration and GPU telemetry scraping. Missing mandatory native prerequisites currently block allocation rather than installing competing operators.
- Build/test the optional CPU staging image and verified serving-volume materialization. Staged Object Storage is not a POSIX model directory. Retained data ownership must be handled separately before metadata destruction when its retention guard applies.
- Implement additional explicitly supported cache/P-D/Ray/gateway adapters and durable shared Responses conversation history as required. Recipe flags alone do not install these services. A vLLM operator is optional rather than a universal prerequisite.

Use `make package` to build `work/packages/oke-llm-discovery.zip`, upload its root to RMS and run discovery. Existing published ZIPs/PARs are not updated by a local rebuild. See [current discovery use](../docs/rms-discovery.md), [model binding and access](../docs/model-binding.md), [module ownership](../docs/repository-layout.md), [component responsibilities](../docs/model-layer-components.md) and [the implementation plan](discovery-html-report-plan.md).
