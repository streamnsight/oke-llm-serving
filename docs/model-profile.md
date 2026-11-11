# Native Terraform model profile

`terraform/modules/model-profile` reads the Hugging Face Hub API and the resolved revision's `config.json` using `hashicorp/http`. Terraform expressions calculate the memory estimate. There is no external program, Bash, Python, OCI SDK or precomputed-profile requirement.

## Inputs and execution

Use `terraform/stacks/discovery` for the combined RMS workflow, or `terraform/examples/model-profile` for model-only inspection:

```sh
terraform -chdir=terraform/examples/model-profile init
terraform -chdir=terraform/examples/model-profile apply
terraform -chdir=terraform/examples/model-profile output -json profile
```

The module accepts `model` (owner/model or a repository URL), `revision`, `context_length`, `concurrency`, `kv_dtype`, `runtime_gib` and `margin`. Context includes both prompt and generation. Defaults are main, 4096 tokens, one sequence, bfloat16 KV, 2 GiB runtime allowance and 20% additional margin. Pin the returned `model.resolved_revision` for deployment.

The initial native lookup supports public repositories. Gated/private models and selecting alternate checkpoint variants are not implemented. An HTTP/config failure fails discovery. A readable model with unsupported estimates returns `memory.status = unsupported` with reasons and null aggregate estimates. No model code executes and no weight payload is downloaded.

## Evidence and limits

Weights come from **Hub-published safetensors element counts by dtype**, multiplied by dtype bytes. These are declared metadata, not independently inspected tensor headers, and may lag upstream changes. The implementation requires counts to sum to the published total and an identifiable canonical `model.safetensors` or `model.safetensors.index.json`. Unsupported/missing counts do not produce a memory recommendation. Additional checkpoint variants are not independently verified. `weights.tensor_elements` is a stored-element count, not a guaranteed count of unique trainable parameters.

The model lookup resolves the requested revision to a commit SHA; config reads use that SHA. The returned profile records the SHA, evidence source and confidence. No tensor-header verification is performed by this implementation.

KV memory uses:

`2 × layers × KV heads × head dimension × live tokens × bytes per KV element`

Live tokens are context length × concurrency. Estimates assume full-context allocation on every layer, without prefix sharing or offload. Sliding-window savings are not assumed. All MoE expert weights are counted; active experts per token do not reduce resident weights.

The numeric estimator covers declared llama, mistral, mixtral, qwen2, qwen2_moe, qwen3 and qwen3_moe conventional attention. It rejects missing/invalid attention dimensions, packed/quantized weights, custom/composite/multimodal architectures, unknown architectures and requested context beyond the declared maximum. A declared architecture is not a serving-engine compatibility certification.

The aggregate recommendation is `(weights + KV + runtime allowance) × (1 + margin)`. Runtime allowance and margin are assumptions, not measured throughput or overhead. Aggregate bytes do **not** establish per-GPU fit or GPU/node count: TP/PP layout, replicated KV heads, execution workspaces, VRAM and topology still need assessment.

## Runtime and validation

RMS must reach Hugging Face over HTTPS and install the HTTP provider from the Terraform Registry. No shell/runtime bootstrap is needed. The implementation is tested locally with native Terraform mocks and public-model lookup; actual RMS job validation remains pending.

```sh
terraform -chdir=terraform/modules/model-profile init -backend=false
terraform -chdir=terraform/modules/model-profile test
```

References: [Hub API](https://huggingface.co/docs/hub/en/api), [ModelInfo metadata](https://huggingface.co/docs/huggingface_hub/package_reference/hf_api#huggingface_hub.hf_api.ModelInfo), [HTTP provider](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http), [RMS provider sourcing](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/providers.htm).
