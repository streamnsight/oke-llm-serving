<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Flint: why discovery does not produce deployment candidates yet

Upstream vLLM supports Flint. Our deployment implementation is incomplete; the rejection is not evidence of upstream incompatibility. The saved RMS discovery result reports exactly two software blockers: unsupported memory/layout estimation and no reviewed engine advertising `FlintForCausalLM`.

## What recipe lookup currently does

`scripts/recipe-model-catalog.mjs` fetches structured recipes and records each model ID, checkpoint variants, task names, source commit/path and dates in `catalogs/models.json`. That is a reference catalog, not a serving-configuration resolver. During discovery, Terraform currently profiles Hugging Face metadata and uses `catalogs/engines.json` for engine admission. It does not fetch/interpret a recipe for the selected model, choose its hardware/variant/strategy, or carry its arguments into deployment. The earlier description of automatic recipe-driven engine selection was ahead of the implementation.

Flint's catalog entry points to [this immutable recipe](https://github.com/vllm-project/vllm/blob/3bc0f430883c575d4076280d8d10d77cd4bfc07c/recipes/models/RecursiveSI/flint.yaml), SHA256 `96ab1b64c6bed851dea6157426f18d8910643d583bf7cb85b3947767d175c323` for the fetched YAML. It still declares `min_vllm_version: nightly`. Separately, the [v0.33.0 registry](https://github.com/vllm-project/vllm/blob/v0.33.0/vllm/model_executor/models/registry.py) explicitly registers `FlintForCausalLM`, and the [release notes](https://github.com/vllm-project/vllm/releases/tag/v0.33.0) announce BF16 and NVFP4 GGUF support. A resolver must keep both pieces of evidence; interpreting the older recipe's nightly field as a strict permanent requirement would reject a supporting stable release.

## Changes needed, beyond editing engines.json

| Layer | Current gap | Required change |
| --- | --- | --- |
| Runtime recipe resolution | The catalog contains recipe references only. | Fetch the selected recipe at an immutable source SHA, validate its schema/model/variant match, and retain its requirements, hardware/strategy evidence and provenance. Unknown/ambiguous requirements stay explicit. |
| Engine/image admission | The only entry is vLLM 0.32.0, lacks Flint, supports only SM80/86/89/90 and declares linux/amd64. | Resolve a supporting release or explicit validated image, verify its registry/source support, pin the actual OCI image digest/platform and check CUDA/driver compatibility. Merely renaming the old entry to 0.33.0 keeps an incorrect image digest. Resolve recipe nightly hints against later release evidence. |
| BF16 memory estimation | The generic estimator rejects `model_type=flint`. | Recognize and validate Flint's GQA/hybrid layout, count **all** expert weights, and estimate KV cache with a clearly conservative policy. Using full context for every layer is a valid upper bound for KV payload; claiming window savings requires accounting for sinks, cache-block rounding and vLLM hybrid cache allocation. |
| Layout/hardware | The generic planner enumerates TP and PP without model-specific recipe constraints. | Separate supported stock vLLM fallbacks from upstream-tested configurations. The recipe validates one GB200 GPU at TP=1 and says TP>1/EP are unvalidated. Released code implements PP, but that is not a tested multi-node deployment. Do not infer all Blackwell/older GPUs or ARM64 compatibility from an architecture name. |
| Deployment arguments | The renderer hardcodes a generic chat command and has no frozen recipe-argument handoff. | Carry selected recipe features/environment/arguments into deployment and revalidate them. Flint reasoning/tool parsing uses `--reasoning-parser glm47`, `--enable-auto-tool-choice`, `--tool-call-parser glm47`, and `--exclude-tools-when-tool-choice-none`. Features should be selected explicitly rather than inferred from arbitrary executable recipe prose. |
| NVFP4 GGUF variant | The current profiler requires canonical safetensors/config metadata. The GGUF repository does not supply its own config/tokenizer. | Treat this as a distinct checkpoint/estimator: resolve BF16 config/tokenizer references, verify GGUF metadata, runtime dependencies (`gguf>=0.19.0`) and resident dequantization. Pass `--hf-config-path RecursiveSI/flint --tokenizer RecursiveSI/flint`. Do not divide BF16 size by four and call it verified. |
| Runtime validation | No Flint GPU test has run here. | Run deployment readiness, inference/streaming, reasoning/tool tests when selected, then the official vLLM benchmark pipeline. Mark memory feasibility and runtime validation separately. |

## BF16 sizing evidence

The SHA-pinned HF config in the successful RMS Plan has 49 layers, 32 query heads, four KV heads, head dimension 128, 256 experts and top-six routing. `layer_types` lists 14 full-attention and 35 sliding-attention layers, with window 513. Two layers use dense rather than MoE MLPs. Hub metadata reports 39,785,287,456 BF16 elements, or **79,570,574,912 weight bytes**. The fact that roughly 2.5B parameters are active per token does not reduce resident weights to 2.5B parameters.

For the saved request (4096 context tokens, concurrency four, BF16 KV), a full-context KV-payload upper bound is `2 * 49 * 4 * 128 * 2 * 4096 * 4 = 1,644,167,168 bytes`. Adding the existing 2 GiB runtime allowance and 20% margin gives approximately **93.2 GiB aggregate**. This is analytical sizing, not measured engine overhead or proof of GPU fit. The recipe lists 96 GB minimum BF16 VRAM and 29 GB for NVFP4; its values do not replace workload-specific estimates.

The previous RMS snapshot contains no B200/GB200/B300/GB300 capacity rows. That observation is scoped to the tenancy, filters and time of that scan; it does not prove regional Blackwell absence. Even complete software admission would not establish a match to the recipe's tested GB200 configuration from that snapshot alone. Other hardware/layouts require explicit fallback assessment and validation.

## Recommended implementation order

1. Add runtime recipe evidence and a frozen model/variant/engine/argument contract shared by discovery and deployment.
2. Add released vLLM image/platform resolution, initially with an explicit version override when recipe nightly requirements cannot be resolved automatically.
3. Implement conservative BF16 Flint estimation and model-specific layout constraints; test admission and rejection cases.
4. Validate a real GPU target. Add NVFP4/GGUF separately after BF16, because it needs a different metadata and resident-memory path.

These are pending implementation tasks. This assessment does not change engine admission or make Flint artificially pass.
