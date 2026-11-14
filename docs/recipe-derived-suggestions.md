<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Recipe-derived deployment suggestions

## Intended behavior

Discovery should provide a starting configuration even when the target GPU has not been tested upstream. Missing estimator coverage should not discard known checkpoint, image, flags, dependencies or topology evidence. Deployment consumes the existing single JSON handoff, selects a suggestion and applies optional overrides. The implementation now emits single-node recipe-derived suggestions alongside the existing candidates and raw sizing options. Multi-node inference and companion-service deployment remain explicit boundaries.

Each suggestion records origin (upstream rendering/adapted/heuristic), upstream validation scope, local validation status, memory-estimate basis, assumptions, changes from upstream and unresolved requirements. Unknown memory and untested hardware remain visible. A partial configuration is useful but cannot be labelled executable until required deployment fields are resolved. Known incompatibility is a rejection; absence of tests is a warning.

## Confirmed sources and implementation gaps

The [vLLM Recipes API](https://recipes.vllm.ai/api) supplies structured argv, environment, image and resolved selection for hardware/variant/strategy queries. The former YAML-only path missed builder defaults and treated missing estimator coverage as a configuration blocker. The JSON path preserves default parsers, recipe images/dependencies and text-serving mode separately from model modality.

Live observations:

- [Qwen BF16 H100](https://recipes.vllm.ai/Qwen/Qwen3.8-27B.json?hardware=h100&variant=default&strategy=single_node_tp) renders TP1, parsers, encoder settings and recipe image `vllm/vllm-openai:qwen38`.
- [Flint BF16 H100](https://recipes.vllm.ai/RecursiveSI/flint.json?hardware=h100&variant=default&strategy=single_node_tp) renders TP1 too. A rendering does not prove memory fit or runtime compatibility.
- Requesting Qwen with `hardware=a10` resolves H200, with the substitution in `selection.adjusted`. It must never be represented as an A10 recipe.
- [Flint's guide](https://recipes.vllm.ai/RecursiveSI/flint) distinguishes tested GB200 TP1 from untested TP/EP fallbacks; its NVFP4 GGUF variant requires BF16 config/tokenizer sources.
- [Qwen's guide](https://recipes.vllm.ai/Qwen/Qwen3.8-27B) covers text serving of a multimodal model. Its YAML BF16 variant gives a 67 GB memory guideline, which is not a workload-specific per-rank bound.

Use argv as data, never evaluate shell command text. Freeze image digests/checkpoint revisions, YAML SHA, response hashes and observation time. Do not claim a live website response came from the pinned YAML SHA unless verified. Preserve and explain differing sources.

## Suggested configuration policy

1. Preserve the requested checkpoint. Expose related precision variants separately, each with its own identity/profile/kernel/image requirements. Resolve config/tokenizer fallback repositories before profiling GGUF checkpoints that omit them.
2. Prefer an exact upstream rendering; verify resolved hardware, variant and strategy, including `selection.adjusted`. Map GPU specifications and topology to OCI shapes. Recipe hardware labels may represent a different device count than an OCI node.
3. Carry model defaults and compatible backend settings. Do not transfer hardware-specific kernels blindly. Preserve recipe image and dependency requirements; treat a generic stable image as an assessed alternative rather than an automatic equivalent.
4. For A10 and other missing profiles, adapt a compatible baseline and enumerate plausible TP values using known attention/head divisibility and engine constraints. Prefer intra-host layouts; evaluate multi-host launch/backend/placement separately. Aggregate bytes alone do not establish valid sharding or parallelism.
5. Combine structured resident-weight/attention/state estimates where supported with recipe memory guidance and explicit runtime/graph margins. Storage bytes are not resident memory. Approximate balanced sharding must be labelled heuristic; replicated components, uneven placement and unknown state remain caveats.
6. Emit a suggestion even if the complete estimator is missing, with its sizing basis and uncertainty. Illustrative hypotheses: Qwen BF16 on H100 80 GB with TP1; Qwen BF16 on four A10 24 GB GPUs with TP4. Neither is validated for the requested workload, and cross-host A10 communication adds risk. Flint BF16 has roughly 79.6 GB of weights, so the rendered H100 TP1 leaves inadequate runtime/KV headroom; suggest larger VRAM or speculative TP2 with the untested fallback clearly recorded.
7. Keep capability, selected serving mode and test coverage separate. A multimodal model may have a valid text-serving recipe without validated image/audio handling. Start with single-node suggestions; multi-node suggestions need an identified backend and launch contract. Do not describe unsupported deployment mechanisms as upstream model incompatibility.

Validation is scoped to exact model revision, image, GPU/topology, workload, features and modality. A hardware-level upstream verified label is not evidence every tuple was tested. Deployment tests loading, inference, streaming, requested APIs/modalities and workload capacity before benchmarking. Record local passed/failed/not-run separately from upstream claims.

## Phases and task list

### Phase 1: complete recipe evidence

- [x] Inspect live API, H100 renderings and A10 substitution behavior.
- [x] Deduplicate bounded API requests by recipe/variant/hardware/strategy, independent of regional AD count; preserve API failures and schema changes.
- [x] Retain argv/env, default features, recipe image/dependencies, related variants and source identities; test adjusted selections.

### Phase 2: suggestion generation

- [x] Separate estimator support, serving mode, configuration origin and validation status.
- [x] Generate exact/adapted/heuristic suggestions with explicit unresolved fields and no false per-rank guarantee.
- [ ] Extend hybrid/recurrent memory estimates incrementally, independently of recipe configuration extraction.
- [x] Cover Qwen H100/A10, Flint BF16/NVFP4, GGUF config fallback, kernel constraints and OCI host topology.

### Phase 3: deployment handoff

- [x] Include suggested configurations and explicit variant alternatives in the single JSON output.
- [x] Select untested suggestions without requiring users to reconstruct inferred settings; retain deployment-only overrides and changes from upstream.

### Phase 4: verification

- [x] Test extraction, adjustment detection, identity, image/dependency selection, memory caveats and generated Kubernetes launches.
- [x] Run Qwen RMS discovery and verify useful suggestions, cache plans and actual JSON-to-deployment handoff.
- [ ] Run Flint RMS discovery with this new suggestion path; BF16/NVFP4 API-based fixtures and config-fallback checks pass locally.
- [ ] Run actual GPU validation/benchmark when allocation is authorized; retain not-run status until then.

## Current use and boundaries

Open the discovery stack's single HTML report link and expand any option. Its infrastructure and independent model stack links are both published during discovery. Each bundle preserves its frozen serving configuration internally; the model stack asks for the cluster and resolves networking and a matching managed pool. Only quantity-confirmed capacity/headroom choices are offered. Ranking uses total allocated GPUs across all required hosts before tie-breakers; it makes no cost/throughput claim. Earlier JSON handoff examples below are historical; see [current discovery usage](rms-discovery.md).

Single-node TP1/2/4/8 suggestions use the greatest of a recipe's decimal-GB memory guideline, an available aggregate payload estimate and a full-layer GQA KV heuristic when BF16 tensor counts/dimensions exist, divide approximately across TP ranks, and add the configured per-GPU runtime allowance. This is a heuristic, with unknown sharding, hybrid/vision state and workload KV overhead clearly labelled. Known context limits and precision hardware restrictions are respected. Unsupported/unknown options stay in raw sizing evidence. Adaptations currently cover BF16 A10/A100/L40S from the portable H100 baseline; quantized builds do not inherit that assumption. API and Docker image responses are HTTP-provider data, not external scripts.

Unselected CPU-offload/LMCache alternatives are not fetched in ordinary discovery; explicit standalone assessment can expose them under recipe evidence, including dependencies and companion commands. They are not enabled by default: Kubernetes cache services, transport and host-memory sizing still require integration. Recipe dependency install commands are never executed automatically; the image and actual inference must be validated in the pipeline. Related variants are metadata alternatives; selecting another checkpoint requires a new discovery run rather than silently switching model identity.

The profile can follow explicit GGUF config/tokenizer references and pins their revisions independently. Automatic staging of these separate repositories is not implemented. Deployment identifies this requirement and requires staged paths with expert argv, instead of using the weights SHA against another repository. Suggested multi-node/PP adaptation and full multimodal validation are not implemented; existing multi-node candidates and expert settings remain available.

## Verification evidence

The final Qwen/Qwen3.8-27B RMS Plan succeeded across all 16 READY subscribed regions. It returned 22 suggestions and four optional cache renderings. The single handoff is retained privately at `work/deployment-inputs.tfvars.json`, with the source plan at `work/latest-discovery-plan.json`. Passing that actual JSON into a deployment Terraform test with cloud resources mocked inherited model, image, TP4/node count and parser settings successfully. No GPUs or DevOps resources were allocated by these checks; no inference or benchmark was run.

Local checks cover 24 planner tests, 10 profile tests, 14 deployment-root tests, seven discovery-root tests, an additional actual-JSON handoff test and 24 script/render checks. Optional LMCache plans retain installation/companion commands but require explicit Kubernetes integration. A local live lookup encountered the host's Docker Hub TLS trust issue; TLS verification was not bypassed, and the RMS image lookup succeeded.

## Capacity eligibility policy

Selectable suggestions, analytical candidates and expert sizing choices require a positive AVAILABLE capacity report covering their requested host count, matching positive limits and observed GPU-unit headroom covering every GPU in those hosts. Zero capacity, missing reports, unsupported/omitted headroom, unknown quota units, insufficient quantity and mismatched AD limits are not selectable. Raw `availability_diagnostics` and `sizing_diagnostics` preserve observations and exclusion reasons; they are not deployment choices. `available_at_scan` describes this eligibility result, independently of model-runtime validation. Deployment still repeats capacity/entitlement checks because the scan does not reserve hardware, and the deployment compartment must have the required permissions/quotas.

Re-evaluating the saved Qwen scan with this policy yields nine choices; the other thirteen all had zero physical capacity. This is a replay of that observation, not a fresh capacity query. Tests cover absent/zero/unknown capacity, quota units, AD scope, insufficient GPU headroom and whole-host entitlement even when TP uses fewer GPUs.
