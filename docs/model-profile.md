# Hugging Face model requirements discovery

This first implementation inspects metadata for one selected safetensors checkpoint and estimates conventional transformer memory. It does not allocate infrastructure, choose a GPU shape, execute repository code or download weight tensor payloads.

## Run from the repository

Python 3.11 or newer is required. There are no runtime dependencies outside the Python standard library.

```sh
PYTHONPATH=src python3 -m oke_llm_serving inspect Qwen/Qwen2.5-0.5B-Instruct \
  --context-length 4096 --concurrency 4
```

Alternatively, install with `python3 -m pip install -e .` inside a virtual environment and run `oke-llm inspect ...`.

For private/gated repositories, set HF_TOKEN in the environment using your normal secret-management workflow. Access approval is still required. Do not put tokens into model URLs, Terraform query values or committed files.

Useful options:

| Option | Meaning |
|---|---|
| --revision | Branch, tag or SHA; all artifact reads use the resolved SHA |
| --checkpoint | Repository-relative safetensors file or index, selecting a specific checkpoint variant |
| --context-length | Total cached tokens per active sequence, including input and generation |
| --concurrency | Simultaneously active sequences at that context length |
| --kv-dtype | bfloat16, float16 or float32 |
| --weight-dtype | checkpoint for existing tensor bytes, or an explicit floating-point conversion estimate |
| --runtime-gib | Aggregate assumed runtime allowance, default 2 GiB |
| --margin | Additional fractional headroom, default 0.2 |

No single runtime allowance fits every model or parallel topology. Both allowance and margin are exposed assumptions, not measured results.

## Profile contract

Successful inspection writes one JSON object to stdout. Failures write a structured error to stderr and exit with code 2. An inspected model with unsupported memory estimation is a successful inspection with `memory.status = unsupported`; consumers must check that status before using estimates.

| Section | Contents |
|---|---|
| schema_version | Currently 1.0 |
| estimator_version | Currently 0.1.0 |
| observed_at | UTC timestamp for this observation |
| model | Repository, requested and resolved revisions, source URL, gating, task and declared license |
| architecture | Declared model type, architecture classes, dense/MoE classification, expert counts, context limit, quantization and provenance |
| weights | Selected checkpoint/shards, tensor data bytes, file bytes when known, tensor element counts by dtype and provenance |
| memory | Estimate status/reasons, explicit assumptions, component byte counts and aggregate estimates when supported |
| warnings | Limitations and unmeasured assumptions |

`tensor_elements` counts stored tensor elements. It is not claimed to be the architecture's exact trainable parameter count, especially with tied or packed weights. Checkpoint tensor bytes exclude safetensors headers. The canonical root checkpoint index/file is preferred; unrelated PyTorch/GGUF formats and alternate subdirectories are not added to it. Without a canonical checkpoint, multiple candidates require explicit selection.

Memory uses full-context KV allocation for all layers, no prefix sharing and no offload. KV is `2 × layers × KV heads × head dimension × context length × concurrency × bytes per KV element`. For sliding-window architectures, ignoring sliding-window savings makes this a full-context upper estimate. MoE estimates count all selected expert weights rather than only experts active per token.

The initial numeric estimator supports declared llama, mistral, mixtral, qwen2, qwen2_moe, qwen3 and qwen3_moe conventional-attention configurations with the required dimensions. This is not a serving-engine compatibility certification. Quantized/packed checkpoints, custom-code, composite/multimodal and other architectures retain weight metadata but do not receive a generic resident-memory estimate. Context beyond the declared maximum is not automatically enabled through RoPE scaling. KV precision conversion support is not inferred for an engine.

Aggregate bytes do not establish per-GPU fit: TP can replicate KV heads, PP partitions layers unevenly, and runtime workspaces depend on execution configuration. Shape selection and per-rank planning are subsequent work.

## Terraform wrapper

```sh
cd terraform/examples/model-profile
terraform init
terraform plan
terraform apply
terraform output -json profile
```

This local example explicitly sets enable_external_analysis=true and uses hashicorp/external and reads the bundled `src` package through the module entry point. It requires the full repository layout, not a copy of the module directory by itself. There is no OCI provider or infrastructure resource in the example. Apply persists the data-source result as Terraform state and outputs; it does not create GPU nodes.

The module returns `profile` as a decoded object. The external protocol returns a string map with one `profile_json` value. Override module input `python_executable` if Python is not on PATH. Pass secrets through the execution environment. Model metadata and estimates are stored in state even though the token is not intentionally included in the result.

For reproducibility, replace the example's `main` revision with `profile.model.resolved_revision`. The observation timestamp changes on refresh; profile consumers should compare pinned model/configuration fields, not require byte-identical timestamped outputs.

External analysis is disabled by default. There is no guarantee that a managed RMS host provides Python 3.11+ or any particular external tools. The preferred RMS path is to generate the profile in a controlled build environment, then pass it as profile_json. The module does not launch Python when that input is supplied. The precomputed profile is authoritative; context/dtype estimator inputs do not recompute it.

The runtime-free example is terraform/examples/model-profile-rms. Supply model_profile_json as a JSON string input (for example through an uncommitted tfvars JSON file or a pipeline variable). This path has been tested locally without external-program execution; the RMS service itself remains untested.

Python remains appropriate for model JSON, binary safetensors headers and tested memory arithmetic. Bash would still need HTTP, JSON and binary-processing dependencies; neither language can guarantee an uncontrolled managed runtime. A versioned build image and precomputed artifact avoid that dependency in RMS. Gated-model authentication remains a live validation item.

## Verification

```sh
PYTHONPATH=src python3 -m unittest discover -s tests -v
terraform fmt -recursive -check terraform
terraform -chdir=terraform/examples/model-profile init -backend=false
terraform -chdir=terraform/examples/model-profile validate
```

Tests cover memory arithmetic, all-expert weight accounting, checkpoint selection, SHA-pinned reads, unsupported estimates, malformed metadata, access errors, the external protocol and bounded Range handling. The client caps individual JSON/header reads at 16 MiB, combined headers at 64 MiB and checkpoint inspection at 1024 shards. These limits prevent an inspection from turning into an unbounded checkpoint scan. HTTP redirects strip credentials across hosts and reject non-HTTPS destinations.

Primary references: [Hub API](https://huggingface.co/docs/hub/en/api), [safetensors header parsing](https://huggingface.co/docs/safetensors/en/metadata_parsing), [Terraform external data source](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external).
