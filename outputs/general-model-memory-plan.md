<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# General model memory sizing plan

## Goal and contract

Discovery must provide useful initial hardware sizing for any accessible model with enough checkpoint evidence, even without a recognized model family or serving recipe. Recognized architectures improve estimates; they must not gate basic arithmetic. A memory estimate does not establish engine support, precision/kernel compatibility, distributed layout fit or available capacity.

For arbitrary custom code, inaccessible weights, ambiguous checkpoint variants or missing metadata, no automatic method can guarantee an accurate total. Return known components plus explicit heuristic scenarios and missing inputs. Allow a user-supplied checkpoint selection, weight size or aggregate planning budget when evidence is insufficient. Never manufacture an evidence-backed bound from a generic percentage.

Primary workflow: a user supplies a model, context and concurrency; discovery explains weight/cache/runtime budgets, shows approximate hardware quantities, then separately evaluates compatible engines, precision, topology, physical capacity and entitlement. Expert users can override assumptions with provenance. Unknown architectures still complete discovery and retain known numeric components.

## Findings from the failing job

- RMS job ending `jzhho7ta2a` succeeded on 2026-11-16; report model revision was `20eb193648df645e73f4572dbf53df50cb4d9fdd`.
- Hub counts: BF16 49,590,974,336; F8_E4M3 2,396,591,751,168; total 2,446,182,725,504 stored tensor elements. These are not automatically logical parameter counts for packed quantization.
- Stored tensor payload is about 2,495.77 decimal GB from these dtypes. Reported checkpoint download is 2,496.10 GB. This already gives useful scale before runtime sizing.
- Current dtype table rejects FP8, quantization disables resident-weight estimates, hybrid detection recognizes only one dense model type, and total sizing depends on a single supported flag. The planner also couples memory support to reviewed engine classes.
- Weight precision is currently coupled to KV dtype through a resident-weight floor. These must be independent. MoE active parameters describe computation, not all resident expert weights under the default no-offload assumption.
- Job workload: context 262,144, concurrency 4. The configuration has 23 full-attention and 69 linear-attention layers. Full-attention BF16 KV payload alone is about 98.78 GB; recurrent state and allocator policy are additional, and this is not a complete cache estimate.

## Design options and recommendation

1. Extend the architecture allowlist per model: small immediate patch, but repeats the same failure for future architectures. Reject as the primary design.
2. Use checkpoint size times one multiplier: broadly available and simple, but misses long-context cache growth, precision expansion and distributed duplication. Keep only as an explicitly low-confidence fallback.
3. Layered evidence and component formulas with generic fallbacks: modest additional structure, broad coverage, explainable uncertainty. Recommended. Architecture-specific refinements are optional and operate on components, not repository names.

Keep arithmetic and ordinary metadata reads in native Terraform where practical. First implementation uses existing Hub metadata/config and canonical checkpoint sizes; range-header enrichment is a separate, bounded step only if the native provider can enforce response-size limits. Otherwise evaluate a small module-owned helper with an explicit RMS runtime contract rather than downloading whole shards or adding a heavyweight runtime dependency silently.

## Phase 1: component estimates and generic fallback

- [ ] Replace the binary global supported flag with component records: numeric value/scenario, evidence, confidence, assumptions and unknowns. Preserve compatible output fields during migration and version the estimator.
- [ ] Select one canonical checkpoint/variant before summing; exclude duplicate formats, optimizer files and unrelated subdirectories. Ambiguity becomes a selection request, not summing every file. Preserve valid partial evidence when another component is unknown.
- [ ] Separate stored bytes, logical parameter count and engine resident bytes. Use dtype-aware stored counts for ordinary float/integer formats including FP8; never equate packed integer elements with logical parameters. Retain independently known storage bytes for unknown dtypes.
- [ ] Evidence order for stored weight payload: verified tensor offsets when available; complete Hub dtype counts; selected index metadata cross-checked against file sizes; selected checkpoint file sizes as an approximation; explicit user input. Record conflicts rather than silently picking a smaller number.
- [ ] Compute resident scenarios independently of KV dtype: native checkpoint precision baseline, explicitly supported expansion/repacking scenarios, and user-specified loading precision. Unknown engine layout gets a labeled planning allowance, not a claim of exact resident bytes. Do not assume hardware without FP8 kernels automatically loads the checkpoint as BF16.
- [ ] Normalize common config field aliases and nested text/component configs; infer attention structure from dimensions/layer declarations rather than a model-name allowlist. Resolve missing KV heads only under a documented architectural assumption.
- [ ] Calculate ordinary attention KV as `2 * full_attention_layers * kv_heads * head_dim * bytes_per_cache_element * context * concurrency`. Handle GQA/MQA; use sliding-window reductions only when cache behavior is established. Never silently clamp an invalid requested context.
- [ ] For hybrid/recurrent/latent-attention and multimodal components, calculate known payloads independently. Refine supported structural primitives; unknown states/workspaces receive explicit low-confidence scenarios. An all-layer dense KV surrogate can be a planning scenario but is not a proven upper bound for arbitrary architectures.
- [ ] For absent dimensions, retain weight-based sizing and expose configurable cache/workspace planning allowances. Defaults must be visible/editable and initially labeled uncalibrated. For absent weights as well, explain which explicit input is needed rather than returning invented totals.
- [ ] Separate runtime fixed overhead per GPU from aggregate payload and proportional uncertainty. Show formula order; avoid applying utilization reserves/margins twice. Validate finite, positive values and handle large counts without overflow or accidental truncation.

## Phase 2: independent hardware screening and report

- [ ] Report checkpoint storage, native-precision weight baseline, cache demand, runtime allowance and planning scenarios even when engine compatibility is unknown or incompatible.
- [ ] Use labels such as metadata-derived, structural estimate and heuristic; distinguish known payload lower bounds from planning ranges. Ranges are scenarios, not statistical confidence intervals or guaranteed bounds.
- [ ] Produce approximate GPU/host quantities from the selected planning scenario, reserving runtime per device. Explicitly label aggregate arithmetic as a lower-bound screening step; it does not prove sharding or per-rank fit.
- [ ] Independently evaluate engine support, precision/kernel support, CPU platform, per-device constraints, TP/PP/EP topology, capacity and quantity-specific entitlement. Keep reasons distinct: insufficient memory, unsupported precision, unverified layout and unavailable capacity.
- [ ] A heuristic memory estimate may support a hardware shortlist with positive capacity and entitlement, but cannot by itself promote a row into an executable deployment choice. Preserve existing trusted onboarding and downstream validation gates.
- [ ] Treat MoE expert residency, embeddings/vision towers and replicated tensors correctly when evidence exists. Never divide aggregate bytes by GPU count and present the quotient as validated per-rank memory.
- [ ] Show the requested context/concurrency prominently and optionally compare a smaller-context scenario without silently replacing the request. Keep one user-facing report link.

## Phase 3: metadata enrichment and breadth validation

- [ ] Add bounded HTTP Range header inspection only where it improves missing/packed/unknown-dtype evidence. Pin all reads to the assessed commit; validate lengths, offsets, shard totals, redirects and response codes. A server ignoring Range must not cause a multi-terabyte download.
- [ ] Cache immutable metadata; bound request concurrency and total bytes. Parsing cost should scale with metadata/tensor entries, not weight bytes. Baseline is O(metadata entries + layers); header enrichment is O(shards + tensor metadata), with no GPU work.
- [ ] Fixtures must include the exact failing Qwen revision, prior dense hybrid model, ordinary dense GQA, MQA, MoE, FP8 mixed precision, packed 4-bit, GGUF selected variant, latent attention, recurrent-only, multimodal, unknown architecture, missing config/counts, ambiguous variants and inaccessible metadata. Distinguish metadata replay from runtime validation.
- [ ] Verify invariants: adding context/concurrency cannot reduce the same scenario's memory; unknown architecture preserves known weight bytes; KV dtype cannot silently change weight precision; partial metadata cannot masquerade as a complete checkpoint; unsupported hardware cannot suppress model sizing.
- [ ] Verify the report remains useful with zero compatible hardware, zero capacity, absent recipe and all-heuristic cache sizing. Validate existing ordinary-model results or document intentional numeric changes.

## Phase 4: validation, calibration and release

- [ ] Run focused executable regressions, `scripts/test-terraform.sh`, Terraform 1.5.7 checks and browser report checks. Validate all three actual generated archive roots from committed source; keep fixtures sanitized and exclude state, credentials and private logs.
- [ ] Compare estimates with existing measured deployments, recording engine/image/revision/precision/workload/layout. Separate demand from an engine's reserved cache capacity and device utilization setting. Do not allocate or recycle GPUs for estimator testing.
- [ ] Test refreshed no-op RMS Plan and discovery-only execution where local/service behavior differs. Confirm no GPU resource mutations. Do not describe a metadata replay as a running-model test.
- [ ] Integrate after relevant validation, rebuild packages after merging, and record package provenance. Hosted bundles and existing RMS uploads require explicit updates; local packaging alone does not update them.

## Acceptance criteria

The failing FP8 model produces its roughly 2.496 TB stored-weight baseline and a numerical planning scenario with the 262,144 x 4 workload, regardless of engine/hardware availability. An unfamiliar architecture with identical evidence also produces a scenario without a code change. Unknown dtypes retain checkpoint-size fallback; missing dimensions retain weight sizing. Insufficient or inaccessible evidence yields a precise missing-input request. No heuristic result claims proven runtime fit or confirmed deployability.

This turn produced a design plan only; implementation and runtime validation remain unchecked.

## References

- Hugging Face metadata-only inspection: https://huggingface.co/docs/safetensors/en/metadata_parsing
- Pinned failing model configuration: https://huggingface.co/Qwen/Qwen3.8-2.4T-A95B-FP8/blob/20eb193648df645e73f4572dbf53df50cb4d9fdd/config.json
- vLLM cache configuration (engine/cache precision and allocation policies): https://docs.vllm.ai/en/stable/api/vllm/config/cache/
