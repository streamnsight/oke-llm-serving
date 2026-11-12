<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

# Project status

Updated November 11, 2026.

Repository consolidation: all built serving/discovery work, research reports, and repository policy/license documents are checked in and integrated into local `main`. Combined validation passed 53 native Terraform tests and six command/manifest/schema tests, including the released Helm chart. Actual RMS/GPU/DevOps validation remains pending.

## Current direction

Two user-facing Resource Manager stacks: discovery from a public model URL and serving assumptions, followed by allocation/DevOps from an explicitly selected configuration. Existing OKE cluster first; retain scarce GPU allocations and scale serving inside them.

Model profiling uses native HTTP/HCL. Regional discovery now uses a compiled Go OCI SDK lookup behind hashicorp/external, enumerating READY regions dynamically without regions.tf. There is no runtime Python/CLI dependency or nested Terraform invocation. Deployment allocation and its admission checks retain native OCI resources. The RMS model input is a URL/ID field; the full alphabetical recipe catalog remains as reference metadata.

## Phase 1 — discovery

- [x] Inspect Hugging Face model metadata through HTTP provider data sources and SHA-pin config reads.
- [x] Estimate conventional full-context KV and all resident MoE weights with explicit context/concurrency/runtime assumptions.
- [x] Label Hub-published counts as declared metadata and return unsupported/null estimates when evidence is insufficient.
- [x] Use native OCI shapes, limits, headroom and capacity reports, keeping root capacity separate from compartment entitlement.
- [x] Implement a single discovery root module and RMS input schema.
- [x] Use checked-in provider aliases and READY-subscription-driven module counts; reject unmapped selected regions.
- [x] Remove local region orchestration and all interpreter-based model paths.
- [x] Finish combined live stack validation and record current test results (18 Terraform test runs; single live plan/apply across 16 subscribed regions).
- [ ] Validate a real RMS job and input-form rendering.

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
- [ ] Validate actual RMS forms/jobs and the full GPU/DevOps/container/RDMA workflow against a selected target.
- [ ] Add a durable Responses/conversation-storage API layer, GPU telemetry sampling and benchmark SLO gates.

The workflow source and local tests are implemented. This is not a claim of successful GPU deployment. No hardware was allocated. Local Terraform mocks cover invalid capacity, quantity entitlement, retained node downsizing, image/model identity and layout contracts; manifest tests exercise the released Helm chart. The benchmark command is tested with stub executables; execution of its actual container remains pending.

The custom Node benchmark runtime was removed. Node's remaining YAML dependency is development-only for manifest/schema verification. Packages exclude tests, local dependencies, caches/state and private artifacts.

The first native metadata estimator supports public conventional-attention models only. Gated/private models, quantized/custom/multimodal estimates and model-specific serving recipes need additional implementation. Capacity is never a reservation or proof of RDMA placement. Root headroom does not prove a child compartment's entitlement.

See [deployment workflow](../docs/deployment-workflow.md), [RMS workflow](../docs/rms-discovery.md), [model-profile limitations](../docs/model-profile.md) and [deployment plan](oci-oke-model-deployment-plan.md).

Recipe list update: the RMS dropdown is generated from commit-pinned vLLM, vLLM recipes and vLLM-Omni YAML sources, including named variants. It is sorted alphabetically by full model ID, without popularity/publisher/task/estimator filters. Recipe dates are retained; optional age filtering uses recipe addition dates, not model release dates. Runtime support remains assessed separately.

Dynamic SDK validation: local lookup successfully covered all 16 READY subscriptions and created 19 diagnostic capacity reports with no hardware allocation. A real Terraform HTTP-profile → SDK lookup → planner integration for Qwen/Qwen2.5-0.5B-Instruct produced 14 estimated candidates and one capacity/headroom shape in the selected Melbourne A10 test. These are discovery results, not serving-runtime validation. The RMS repair Plan using the prior native configuration returned INTERNAL_SERVICE_ERROR without Terraform logs; SDK-based RMS validation remains pending.
