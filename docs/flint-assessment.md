<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Flint: upstream evidence, resolution and expert deployment

Upstream vLLM supports Flint. Runtime recipe/image resolution is now implemented: the live lookup selected stable v0.33.0, pinned the platform digest and extracted requested reasoning/tool arguments. The built-in per-rank estimator remains unsupported; discovery now supplies separately labeled aggregate sizing options and an expert deployment handoff. See [the runtime workflow](runtime-serving-resolution.md) for inputs and validation boundaries.

## Recipe and release evidence

The live recipe JSON endpoint resolves model aliases and upstream source references. Discovery fetches the selected YAML at a live-resolved immutable source SHA, inspects its variant/features/hardware/strategy metadata and resolves an engine image. No static model/engine catalog is used.

Flint's catalog entry points to [this immutable recipe](https://github.com/vllm-project/vllm/blob/3bc0f430883c575d4076280d8d10d77cd4bfc07c/recipes/models/RecursiveSI/flint.yaml), SHA256 `96ab1b64c6bed851dea6157426f18d8910643d583bf7cb85b3947767d175c323` for the fetched YAML. It still declares `min_vllm_version: nightly`. Separately, the [v0.33.0 registry](https://github.com/vllm-project/vllm/blob/v0.33.0/vllm/model_executor/models/registry.py) explicitly registers `FlintForCausalLM`, and the [release notes](https://github.com/vllm-project/vllm/releases/tag/v0.33.0) announce BF16 and NVFP4 GGUF support. A resolver must keep both pieces of evidence; interpreting the older recipe's nightly field as a strict permanent requirement would reject a supporting stable release.

## Implementation status

| Layer | Current gap | Current role / remaining checks |
| --- | --- | --- |
| Runtime recipe resolution | Runtime lookup is implemented; the catalog supplies aliases only. | Fetch the selected recipe at an immutable source SHA, validate its schema/model/variant match, and retain its requirements, hardware/strategy evidence and provenance. Unknown/ambiguous requirements stay explicit. |
| Engine/image admission | Dynamic stable/nightly source lookup and platform digest resolution are implemented; the old catalog is retained only for legacy deployment inputs. | Resolve a supporting release or explicit validated image, verify its registry/source support, pin the actual OCI image digest/platform and check CUDA/driver compatibility. Merely renaming the old entry to 0.33.0 keeps an incorrect image digest. Resolve recipe nightly hints against later release evidence. |
| BF16 memory estimation | Per-rank estimation still rejects `model_type=flint`; a separate full-context KV-payload bound is available for expert sizing. | Recognize and validate Flint's GQA/hybrid layout, count **all** expert weights, and estimate KV cache with a clearly conservative policy. Using full context for every layer is a valid upper bound for KV payload; claiming window savings requires accounting for sinks, cache-block rounding and vLLM hybrid cache allocation. |
| Layout/hardware | Runtime candidates now distinguish exact selected recipe hardware/TP matches from configurations requiring expert settings. Aggregate-only sizing options never invent TP/PP. | Separate supported stock vLLM fallbacks from upstream-tested configurations. The recipe validates one GB200 GPU at TP=1 and says TP>1/EP are unvalidated. Released code implements PP, but that is not a tested multi-node deployment. Do not infer all Blackwell/older GPUs or ARM64 compatibility from an architecture name. |
| Deployment arguments | Frozen recipe arguments/environment and explicit expert overrides now reach both Helm and distributed pods. | Carry selected recipe features/environment/arguments into deployment and revalidate them. Flint reasoning/tool parsing uses `--reasoning-parser glm47`, `--enable-auto-tool-choice`, `--tool-call-parser glm47`, and `--exclude-tools-when-tool-choice-none`. Features should be selected explicitly rather than inferred from arbitrary executable recipe prose. |
| NVFP4 GGUF variant | The current profiler requires canonical safetensors/config metadata. The GGUF repository does not supply its own config/tokenizer. | Treat this as a distinct checkpoint/estimator: resolve BF16 config/tokenizer references, verify GGUF metadata, runtime dependencies (`gguf>=0.19.0`) and resident dequantization. Pass `--hf-config-path RecursiveSI/flint --tokenizer RecursiveSI/flint`. Do not divide BF16 size by four and call it verified. |
| Runtime validation | No Flint GPU test has run here. | Run deployment readiness, inference/streaming, reasoning/tool tests when selected, then the official vLLM benchmark pipeline. Mark memory feasibility and runtime validation separately. |

## BF16 sizing evidence

The SHA-pinned HF config in the successful RMS Plan has 49 layers, 32 query heads, four KV heads, head dimension 128, 256 experts and top-six routing. `layer_types` lists 14 full-attention and 35 sliding-attention layers, with window 513. Two layers use dense rather than MoE MLPs. Hub metadata reports 39,785,287,456 BF16 elements, or **79,570,574,912 weight bytes**. The fact that roughly 2.5B parameters are active per token does not reduce resident weights to 2.5B parameters.

For the saved request (4096 context tokens, concurrency four, BF16 KV), a full-context KV-payload upper bound is `2 * 49 * 4 * 128 * 2 * 4096 * 4 = 1,644,167,168 bytes`. Adding the existing 2 GiB runtime allowance and 20% margin gives approximately **93.2 GiB aggregate**. This is analytical sizing, not measured engine overhead or proof of GPU fit. The recipe lists 96 GB minimum BF16 VRAM and 29 GB for NVFP4; its values do not replace workload-specific estimates.

The previous RMS snapshot contains no B200/GB200/B300/GB300 capacity rows. That observation is scoped to the tenancy, filters and time of that scan; it does not prove regional Blackwell absence. Even complete software admission would not establish a match to the recipe's tested GB200 configuration from that snapshot alone. Other hardware/layouts require explicit fallback assessment and validation.

## Remaining validation and estimation work

1. Runtime recipe evidence and frozen model/variant/engine/argument handoff are implemented and tested locally.
2. Stable/nightly image/platform resolution is implemented. Explicit nightly selection remains supported; stable can supersede an old nightly hint when its source registry declares the architecture.
3. Dedicated per-rank Flint estimation remains future work. Aggregate payload sizing is labeled separately; an expert must supply topology and a rank-memory bound.
4. Real GPU inference/performance validation and the NVFP4/GGUF profiling path remain pending.

The resolver does not treat an A10/H100 alternative as upstream-tested. Expert deployment retains immutable identity, CPU-platform, VRAM, host GPU-count, allocation geometry and fresh capacity/entitlement checks, followed by automatic deployment validation.
