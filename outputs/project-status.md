<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

# Project status

Updated November 11, 2026.

Repository consolidation: all built serving/discovery work, research reports, and repository policy/license documents are checked in and integrated into local `main`. Combined validation passed 53 native Terraform tests and six command/manifest/schema tests, including the released Helm chart. RMS discovery Plan validation has now succeeded; GPU/DevOps validation remains pending.

## Current direction

Two user-facing Resource Manager stacks: discovery from a public model URL and serving assumptions, followed by allocation/DevOps from an explicitly selected configuration. Existing OKE cluster first; retain scarce GPU allocations and scale serving inside them.

Model profiling uses native HTTP/HCL. Regional discovery now uses Bash/OCI CLI/jq behind hashicorp/external, enumerating READY regions dynamically without regions.tf. There is no Go build, custom Python script or nested Terraform invocation. Deployment allocation and its admission checks retain native OCI resources. The RMS model input is a URL/ID field; the full alphabetical recipe catalog remains as reference metadata. Runtime vLLM recipe/source/image lookup now uses HTTP/HCL and passes a frozen digest/argv/environment contract into deployment. The engine catalog is a legacy fallback. GPU alternatives with undetermined configurations have an explicit expert handoff.

## Phase 1 — discovery

- [x] Inspect Hugging Face model metadata through HTTP provider data sources and SHA-pin config reads.
- [x] Estimate conventional full-context KV and all resident MoE weights with explicit context/concurrency/runtime assumptions.
- [x] Label Hub-published counts as declared metadata and return unsupported/null estimates when evidence is insufficient.
- [x] Use native OCI shapes, limits, headroom and capacity reports, keeping root capacity separate from compartment entitlement.
- [x] Implement a single discovery root module and RMS input schema.
- [x] Discover READY subscribed regions dynamically through OCI CLI; no hardcoded provider-alias region list.
- [x] Remove local region orchestration and all interpreter-based model paths.
- [x] Finish combined live stack validation and record current test results (18 Terraform test runs; single live plan/apply across 16 subscribed regions).
- [x] Validate a real RMS discovery Plan across all 16 subscribed regions using the CLI replacement.
- [ ] Verify RMS input-form rendering.

Local model-only native apply succeeded for Qwen/Qwen2.5-0.5B-Instruct: 988,065,536 weight bytes and a 3.729 GiB aggregate estimate at 4096 tokens × four concurrent sequences, including assumed 2 GiB runtime and 20% margin. This is not a per-GPU fit or throughput measurement.

An initial live capacity investigation covered all 16 READY subscriptions and 26 ADs using native OCI reports. Five regions listed no GPU shapes; reported positive capacity existed in ten regions, with Chicago's listed shapes out of capacity. No GPU hardware was allocated. The combined single-state discovery stack also completed live validation; see the validation record and capacity report for the newer snapshot.

## Phase 2 — layout, infrastructure and delivery

- [x] Add sourced GPU memory/compute capability, versioned engine-image and component catalogs.
- [x] Extract model-card version hints and attention/chat-template metadata; estimate compute-dtype resident weights.
- [x] Produce TP/PP candidates and export immutable deployment variables.
- [x] Implement selected existing-cluster GPU/CPU pools, supported RDMA Compute Cluster placement, fresh capacity/quantity entitlement admission and retained-capacity safeguards.
- [x] Implement OCI DevOps deploy, automatically chained validation, and separately triggered benchmark pipelines, private evidence and bootstrap RBAC.
- [x] Render pinned production-stack/vLLM recipes and LeaderWorkerSet/native MP across nodes.
- [x] Replace the custom benchmark client with official `vllm bench serve` in a pinned CPU image.
- [x] Add all-task recipe-model catalog refresh and committed-source RMS packaging hooks.
- [ ] Validate RMS forms and the full GPU/DevOps/container/RDMA workflow against a selected target.
- [ ] Add a durable Responses/conversation-storage API layer, GPU telemetry sampling and benchmark SLO gates.

The workflow source and local tests are implemented. This is not a claim of successful GPU deployment. No hardware was allocated. Local Terraform mocks cover invalid capacity, quantity entitlement, retained node downsizing, image/model identity and layout contracts; manifest tests exercise the released Helm chart. The benchmark command is tested with stub executables; execution of its actual container remains pending.

The custom Node benchmark runtime was removed. Node's remaining YAML dependency is development-only for manifest/schema verification. Packages exclude tests, local dependencies, caches/state and private artifacts.

The first native metadata estimator supports public conventional-attention models only. Gated/private models, quantized/custom/multimodal estimates and model-specific serving recipes need additional implementation. Capacity is never a reservation or proof of RDMA placement. Root headroom does not prove a child compartment's entitlement.

See [deployment workflow](../docs/deployment-workflow.md), [RMS workflow](../docs/rms-discovery.md), [model-profile limitations](../docs/model-profile.md) and [deployment plan](oci-oke-model-deployment-plan.md).

Recipe list update: the RMS dropdown is generated from commit-pinned vLLM, vLLM recipes and vLLM-Omni YAML sources, including named variants. It is sorted alphabetically by full model ID, without popularity/publisher/task/estimator filters. Recipe dates are retained; optional age filtering uses recipe addition dates, not model release dates. Runtime support remains assessed separately.

Dynamic SDK validation: local lookup successfully covered all 16 READY subscriptions and created 19 diagnostic capacity reports with no hardware allocation. A real Terraform HTTP-profile → SDK lookup → planner integration for Qwen/Qwen2.5-0.5B-Instruct produced 14 estimated candidates and one capacity/headroom shape in the selected Melbourne A10 test. These are discovery results, not serving-runtime validation. The RMS repair Plan using the prior native configuration returned INTERNAL_SERVICE_ERROR without Terraform logs; SDK-based RMS validation remains pending.


RMS discovery validation: a real Plan completed successfully using the compiled OCI SDK helper, assessing all 16 READY subscribed regions in the test tenancy. RMS authentication required its InstancePrincipal mode plus delegated caller token; raw instance-principal calls alone were denied. The model form now takes a Hugging Face URL or ID directly. Flint remains outside this stack's estimator/engine coverage. The user has requested investigation of using the existing OCI CLI/Python SDK runtime instead of packaging Go binaries; runtime availability is being checked before that decision. The browser's Resource Manager pages remain blank, so revised form rendering is not yet verified.

Runtime probe confirmed OCI CLI and Python OCI SDK 2.189.0 on Python 3.9.25 in the actual RMS job host. The temporary probe deliberately stopped before discovery and the stack configuration was restored to the working discovery package. Go packaging is unnecessary for this inspected environment; replacement with a CLI-backed helper remains to be implemented.


CLI replacement local validation: six CLI fixture tests and five discovery Terraform tests passed, including exact four-region batches, unknown capacity, zero/AD-matched limits, API failures and delegated auth. The live Melbourne/A10 CLI check queried entitlement and a fresh physical report, matching the old inventory/capacity JSON schema; physical capacity was zero at that observation. Both RMS ZIPs now contain shell/jq source and no Go source, compiled binaries or Node dependencies. The CLI-only RMS Plan succeeded: 16 subscribed/assessed regions, 26 headroom queries and 19 physical capacity reports. No GPU nodes were allocated. The downloaded plan is retained privately in work/cli-rms-discovery-plan.json. See [Flint assessment](../docs/flint-assessment.md) for confirmed software admission gaps and pending recipe/runtime integration.


Runtime serving-resolution feature: nine native resolver tests, 14 planner tests, eight profile tests, seven deployment-root tests and five discovery-root tests passed. Nineteen Node checks passed, with updated selection/render checks also verified against the released Helm chart. Live HTTP/HCL lookup selected vLLM v0.33.0 for BF16 Flint despite its recipe nightly hint, preserving source evidence and a platform image digest. Against the saved regional inventory, discovery produced 56 aggregate-sizing options and identified GB200/ARM64 as the upstream recipe target. Expert options require explicit topology and a per-rank GPU-memory bound; they are not runtime-certified layouts. See [runtime serving resolution](../docs/runtime-serving-resolution.md). Combined RMS Plan verification succeeded across all 16 subscribed regions: stable vLLM 0.33.0 is digest-pinned for Flint and 56 expert sizing options are reported, alongside the GB200/ARM64 recipe target. No automatic per-rank Flint layout is claimed; no GPU deployment or benchmark has run. The new plan is retained privately at work/runtime-resolution-rms-plan.json.

Discovery connection UX: the bootstrap-region selector is hidden, local region input is optional, and the CLI discovers the actual tenancy home region from subscription metadata. It uses that endpoint for subscription discovery while continuing to scan all READY regions unless a filter is supplied. The returned discovery JSON includes home_region. Verified with seven CLI tests, six Terraform tests, the schema check and a live no-region-override CLI run (home Chicago, scoped scan Melbourne).

Discovery/deployment handoff: discovery now assesses model metadata, recipes, stable/nightly images and GPU options without requesting deployment overrides. Its `deployment_inputs` output is the single JSON document consumed unchanged by deployment (tfvars object locally, literal JSON text in RMS). Target selection, image/platform/channel, optional recipe features and expert configuration belong to deployment. Local verification passed 24 script/render checks, 10 resolver tests, 16 planner tests, nine model-profile tests, seven discovery-root tests and 12 deployment-root tests.

RMS regressions found while changing the selected model: a saved literal `${session.region}` caused an invalid OCI endpoint, blank shape list entries hid every GPU, and uncatalogued shapes could crash image selection. The helper now infers its first endpoint from its authenticated principal/profile, ignores stale template values and blank filters, and the planner retains unknown shapes diagnostically. Checkpoint-download size remains separate from resident GPU-memory estimates. These checks do not prove a GPU allocation or serving-runtime configuration.

The corrected live Qwen/Qwen3.8-27B RMS Plan succeeded across all 16 READY regions. It selected stable vLLM 0.33.0 and emitted the one-document deployment handoff at work/deployment-inputs.tfvars.json. Zero automatic candidates and 56 expert hardware options are expected for its unsupported composite/multimodal estimator; GPU counts remain unknown. This is a successful assessment, not a validated deployment.

Recipe JSON API implementation: discovery now provides ranked, untested single-node GPU configurations with recipe-specific pinned images, parser flags/environment, workload-aware heuristic memory budgets, TP/node count, provenance and warnings. Deployment selects a suggestion's own configuration via selection_id without reconstructing its settings. The final Qwen RMS Plan succeeded across 16 READY regions with 22 suggestions and four optional CPU-offload/LMCache plans. Actual RMS JSON passed deployment planning with cloud modules mocked. The handoff is privately retained at work/deployment-inputs.tfvars.json. No GPU inference, allocation or benchmark was performed. See docs/recipe-derived-suggestions.md for cache companions, multi-node inference, modality and external GGUF-config staging boundaries.

Capacity eligibility correction: all selectable suggestions/candidates/expert sizing options now require positive physical capacity for the required hosts and quantity-confirmed headroom in explicit GPU units. Unknown/zero/insufficient observations remain diagnostic only. Replaying the saved Qwen scan reduces 22 suggestions to nine; the other thirteen were known zero-capacity observations, not unknown physical availability. No fresh capacity query or GPU allocation is implied by that replay.
