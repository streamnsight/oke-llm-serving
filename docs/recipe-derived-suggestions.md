<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Recipe-derived deployment suggestions

## Intended behavior

Discovery should provide a starting configuration even when the target GPU has not been tested upstream. Missing estimator coverage should not discard known checkpoint, image, flags, dependencies or topology evidence. Deployment consumes the existing single JSON handoff, selects a suggestion and applies optional overrides. This document is a design and implementation plan; the current implementation still returns undetermined hardware options in these cases.

Each suggestion records origin (upstream rendering/adapted/heuristic), upstream validation scope, local validation status, memory-estimate basis, assumptions, changes from upstream and unresolved requirements. Unknown memory and untested hardware remain visible. A partial configuration is useful but cannot be labelled executable until required deployment fields are resolved. Known incompatibility is a rejection; absence of tests is a warning.

## Confirmed sources and implementation gaps

The [vLLM Recipes API](https://recipes.vllm.ai/api) supplies structured argv, environment, image and resolved selection for hardware/variant/strategy queries. Our YAML subset extraction misses the builder's default reasoning/tool features. Recipe images/dependencies currently become expert blockers rather than actionable requirements. Missing memory estimators stop suggested topology. The blanket text-generation tag check also rejects text serving of a multimodal architecture.

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
- [ ] Deduplicate bounded API requests by recipe/variant/hardware/strategy, independent of regional AD count; preserve API failures and schema changes.
- [ ] Retain argv/env, default features, recipe image/dependencies, related variants and source identities; test adjusted selections.

### Phase 2: suggestion generation

- [ ] Separate estimator support, serving mode, configuration origin and validation status.
- [ ] Generate exact/adapted/heuristic suggestions with explicit unresolved fields and no false per-rank guarantee.
- [ ] Extend hybrid/recurrent memory estimates incrementally, independently of recipe configuration extraction.
- [ ] Cover Qwen H100/A10, Flint BF16/NVFP4, GGUF config fallback, kernel constraints and OCI host topology.

### Phase 3: deployment handoff

- [ ] Include suggested configurations and explicit variant alternatives in the single JSON output.
- [ ] Select untested suggestions without requiring users to reconstruct inferred settings; retain deployment-only overrides and changes from upstream.

### Phase 4: verification

- [ ] Test extraction, adjustment detection, identity, image/dependency selection, memory caveats and generated Kubernetes launches.
- [ ] Run Qwen/Flint RMS discovery and verify useful suggested configurations alongside raw hardware observations.
- [ ] Run actual GPU validation/benchmark when allocation is authorized; retain not-run status until then.
