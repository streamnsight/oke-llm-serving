<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

# Native Terraform model profile

`modules/discovery/model-profile` reads the Hugging Face Hub API and the resolved revision's `config.json` using `hashicorp/http`. Terraform expressions calculate the memory estimate. There is no external program, Bash, Python, OCI SDK or precomputed-profile requirement.

## Inputs and execution

Use `.` for the combined RMS workflow, or `examples/model-profile` for model-only inspection:

```sh
terraform -chdir=examples/model-profile init
terraform -chdir=examples/model-profile apply
terraform -chdir=examples/model-profile output -json profile
```

The module accepts `model` (owner/model or a repository URL), `revision`, `context_length`, `concurrency`, `kv_dtype`, `runtime_gib` and `margin`. Context includes both prompt and generation. Defaults are main, 4096 tokens, one sequence, bfloat16 compute/KV, 2 GiB runtime allowance and 20% additional margin. Pin the returned `model.resolved_revision` for deployment.

The initial native lookup supports public repositories. Gated/private models and selecting alternate checkpoint variants are not implemented. An HTTP/config failure fails discovery. A readable model with unsupported estimates returns `memory.status = unsupported` with reasons and null aggregate estimates. No model code executes and no weight payload is downloaded.

## Evidence and limits

Weights come from **Hub-published safetensors element counts by dtype**, multiplied by dtype bytes. These are declared metadata, not independently inspected tensor headers, and may lag upstream changes. The implementation requires counts to sum to the published total and an identifiable canonical `model.safetensors` or `model.safetensors.index.json`. Unsupported/missing counts do not produce a memory recommendation. Additional checkpoint variants are not independently verified. `weights.tensor_elements` is a stored-element count, not a guaranteed count of unique trainable parameters.

The model lookup resolves the requested revision to a commit SHA; config, tokenizer configuration and model-card reads use that SHA. The returned profile records the SHA, evidence source and confidence. No tensor-header verification is performed by this implementation.

KV memory uses:

`2 × layers × KV heads × head dimension × live tokens × bytes per KV element`

Live tokens are context length × concurrency. Estimates assume full-context allocation on every layer, without prefix sharing or offload. Sliding-window savings are not assumed. All MoE expert weights are counted; active experts per token do not reduce resident weights.

The numeric estimator covers declared llama, mistral, mixtral, qwen2, qwen2_moe, qwen3 and qwen3_moe conventional attention. It rejects missing/invalid attention dimensions, packed/quantized weights, custom/composite/multimodal architectures, unknown architectures and requested context beyond the declared maximum. A declared architecture is not a serving-engine compatibility certification.

The aggregate recommendation is `(weights + KV + runtime allowance) × (1 + margin)`. Runtime allowance and margin are assumptions, not measured throughput or overhead. Aggregate bytes do **not** establish per-GPU fit or GPU/node count: TP/PP layout, replicated KV heads, execution workspaces, VRAM and topology still need assessment.

## Runtime and validation

RMS must reach Hugging Face over HTTPS and install the HTTP provider from the Terraform Registry. No shell/runtime bootstrap is needed. The implementation is tested locally with native Terraform mocks and public-model lookup; actual RMS job validation remains pending.

```sh
terraform -chdir=modules/discovery/model-profile init -backend=false
terraform -chdir=modules/discovery/model-profile test
```

References: [Hub API](https://huggingface.co/docs/hub/en/api), [ModelInfo metadata](https://huggingface.co/docs/huggingface_hub/package_reference/hf_api#huggingface_hub.hf_api.ModelInfo), [HTTP provider](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http), [RMS provider sourcing](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/providers.htm).

## Serving assessment

The profile exposes structured attention dimensions, chat-template presence, and bounded regex matches for explicit vLLM/SGLang version statements in the pinned model card. Matches include source lines; they are evidence for review, not executable deployment instructions. Missing matches do not establish compatibility. The deployment planner compares supported architectures and simple stable-version constraints against the reviewed engine catalog.

`weights.tensor_data_bytes` describes checkpoint storage. `memory.weight_bytes` reserves at least two bytes per published element for float16/bfloat16 compute, or four for float32, while retaining a larger checkpoint estimate. The initial recipe sets compute dtype from `kv_dtype` and leaves vLLM KV dtype at `auto`. The deployment planner applies the runtime allowance to each GPU rank and accounts conservatively for uneven pipeline stages, embeddings and KV-head replication. Estimates still require runtime validation.

## Partial hybrid estimates and the planning budget

Estimator `terraform-metadata-0.2.0` keeps the weight estimate when a complete architecture estimate is unavailable, provided canonical, consistent unquantized Hub counts exist. Complete `memory.status` remains unsupported, so publishing known weights does not admit an analytical layout automatically.

For Qwen/Qwen3.8-27B at revision `37561816e66b5b9153b1b64c10968c18c1e6f4a0`, 4,096 context tokens and four sequences:

| Component | Estimate | Meaning |
|---|---:|---|
| Resident BF16 weights | 55.56 GB | Hub-published 27,781,427,952 elements × 2 bytes |
| Full-attention KV payload | 1.07 GB | 2 × 16 full-attention layers × 4 KV heads × 256 dimensions × 2 bytes × 4,096 × 4 |
| Linear-attention cache / vision workspace | Unknown | 48 linear layers need engine-specific cache/state handling; media dimensions/batch are not profiled |
| KV surrogate used for planning | 4.29 GB | Deliberately treats all 64 text layers as full attention; not the actual hybrid cache allocation |
| Planning payload budget | 71.83 GB | max(recipe minimum 67 GB, analytical/fallback estimate if supported, (55.56 + 4.29) × 1.20) |
| Additional runtime allowance | 2.15 GB per GPU | Added after approximately dividing the planning payload across TP ranks |

The sizing check is `payload budget / TP + runtime allowance <= 90% of device VRAM` for recipe suggestions. Under these assumptions it selects TP4 on A10 24 GB and A100 40 GB, and TP2 on A100 80 GB. An eight-GPU A100 host therefore packs two or four complete replicas respectively. This does not assert that these shapes have capacity in a particular region, that the model is evenly sharded, or that runtime fit has been validated.

The all-layer KV surrogate supplies heuristic planning space; it is **not a bound on recurrent-state, cache-page padding, vision or CUDA graph memory**. The report shows the known full-attention payload and the planning surrogate separately, and keeps the complete runtime estimate unestablished. [vLLM hybrid allocation](https://docs.vllm.ai/en/latest/design/hybrid_kv_cache_manager/) explains why state grouping/padding and prefix-cache checkpoints depend on the engine. Unknown layer types do not inherit the Qwen partial formula. Quantized weights keep their dedicated-estimator requirement.
