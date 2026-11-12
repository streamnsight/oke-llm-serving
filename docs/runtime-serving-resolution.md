<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Runtime recipe/image discovery and expert configurations

Discovery now looks up the selected model's structured vLLM recipe during the Terraform run. `catalogs/models.json` supplies model/variant aliases and legacy recipe references; it is not a runtime compatibility allowlist. The resolver first tries the model's current canonical path in vllm-project/vllm, then a known legacy owning repository when needed. It resolves each source's main branch to a commit and reads YAML at that immutable SHA. There is no Python/Bash model inspector or executable recipe prose.

`terraform/modules/serving-resolution` uses only HTTP-provider data and HCL (`yamldecode`, JSON and expressions). It extracts the matching checkpoint variant, base and variant arguments/environment, default-hardware overrides, selected optional features, upstream hardware labels and strategy evidence. It does not install packages or execute launch commands from the guide. Missing recipes, ambiguous variants, unresolved templates, custom-image requirements and conflicting managed flags are returned as issues requiring expert configuration. HTTP access/rate-limit failures fail the lookup rather than pretending a recipe is absent.

## Engine policy

- `engine_channel = "auto"` prefers the latest stable `vX.Y.Z` tag observed in the first 100 upstream tags, checks the SHA-pinned source registry for the declared model architecture, and falls back to nightly when stable architecture/minimum coverage is missing or a variant explicitly requires nightly.
- `engine_channel = "stable"` forbids automatic nightly fallback. `engine_version = "0.33.0"` selects an exact stable version. Blank optional version input is treated as unset.
- `engine_channel = "nightly"` selects nightly explicitly. Do not also provide a stable version override.
- A recipe's older `min_vllm_version: nightly` is retained as evidence; stable source architecture support can supersede that hint. An explicit `nightly_required` variant remains distinct. Unknown version expressions require review.
- GitHub's `/releases/latest` is not used: it currently reports an rc tag despite the stable v0.33.0 tag and image existing.
- Docker Hub platform metadata selects an immutable image digest for `engine_platform` (`linux/amd64` or `linux/arm64`). A missing platform digest stays unresolved. The selected source and image tag are upstream evidence, not independent proof that image contents match the source or that the model will run.

`catalogs/engines.json` remains a legacy/offline fallback for pre-existing deployment inputs. Discovery passes its dynamically resolved engine to the planner; a new version does not require editing that file. Deployment consumes the frozen `serving_configuration` object instead of re-running discovery against moving tags.

Recipe features are explicit. For Flint reasoning and tools, set:

```hcl
recipe_features = ["reasoning", "tool_calling"]
```

The resolver preserves `--reasoning-parser glm47`, `--enable-auto-tool-choice`, `--tool-call-parser glm47`, and `--exclude-tools-when-tool-choice-none`. With no optional features selected, only base/variant/hardware arguments are applied. Check `recipe.available_features`, `recipe.install_requirements` and `recipe.issues` in the output before selecting a configuration.

## Three distinct results

`discovery.serving_configuration` records the frozen model SHA, recipe source SHA/hash, variant/features/arguments/environment, engine source SHA, platform image digest and selection rationale. `resolved_requires_validation` means structured lookup succeeded, not that inference passed.

`assessment.candidates` remains the per-rank estimator's output. Dynamic candidates additionally distinguish an upstream hardware/TP recipe match from `undetermined_requires_expert`. A match requires the selected recipe hardware/platform, a verified upstream hardware label, a declared single-node TP strategy, its explicit TP value and PP=1. Upstream hardware evidence still does not equal runtime validation in this tenancy.

`assessment.sizing_options` lists other visible NVIDIA GPU shapes with known catalog VRAM/CPU metadata even when the per-rank estimator is unsupported. Each option carries capacity/limit/headroom observations, image-platform compatibility and a configuration-undetermined label. Known estimates are estimated GPU/node counts for the stated aggregate payload budget; TP, PP, communication, per-rank balance and model-specific scratch are not inferred. Unknown payload sizing stays null. These are alternatives for expert assessment, not executable deployment recommendations.

For BF16 Flint, structured GQA full/sliding layer metadata permits a full-context KV-payload bound across every layer and all resident expert weights. At context 4096, concurrency four, BF16, 2 GiB runtime allowance and 20% margin, this is about 93.2 GiB aggregate. One 24 GB A10 is insufficient; the aggregate budget corresponds to an estimated minimum of five A10 GPUs under 90% utilization. This is not a mathematical lower bound on actual hardware requirements: conservative KV assumptions can overestimate payload, while per-rank overhead can increase it. It does not establish that five GPUs form a valid layout or that 8 A10s will run well. Expert TP/PP and a per-rank memory bound remain required. Quantized/GGUF resident-memory estimation is still unsupported.

`assessment.recipe_hardware_targets` identifies catalog shapes/platforms matching the upstream verified hardware labels, including targets absent from the current scan. When observed limits are zero it suggests a limit increase; missing shape observations mean investigate entitlement/capacity, not global unavailability. GB200 (Grace/ARM64) is not silently treated as an x86 B200 host. The engine platform must match the selected OKE image/node CPU. OCI allocates whole shape instances: an eight-GPU bare-metal node reserves all eight GPUs even if a selected model replica uses fewer.

## Expert handoff

Start with `terraform/stacks/deployment/target.example.json`. For an undetermined option, add:

```json
{
  "expert_configuration": true,
  "tensor_parallel_size": null,
  "pipeline_parallel_size": null,
  "node_count": null,
  "replicas": 1,
  "expert_rank_memory_gib": null
}
```

Replace nulls with expert-selected settings. The rank-memory value must bound weights, KV and runtime on **each GPU rank**; the aggregate estimate is not sufficient. `node_count` must equal PP × replicas, and TP must fit the GPUs per host. Optional `engine_args` and `engine_env` replace the extracted recipe argv/environment. Managed model identity, topology and memory flags must use dedicated deployment variables; conflicting flags are rejected.

An expert can also supply `engine_image` (digest-pinned), `engine_version` and `engine_platform` together to override the resolved image deliberately. This updates the frozen handoff and remains unvalidated; an arbitrary tag is not accepted. No catalog edit is necessary.

Export either a candidate ID or sizing-option ID:

```sh
bash scripts/select-deployment.sh work/discovery.json OPTION_ID target.json \
  > work/deployment.tfvars.json
```

The script refuses an undetermined option without explicit expert settings. The deployment stack rechecks model/image identity, CPU platform, rank VRAM, GPU count, allocation geometry, storage and fresh physical capacity/entitlement. Expert mode relaxes unsupported software/layout inference; it does not bypass those infrastructure checks. Package both stacks with `make package`. In RMS, load the exported variables, preserving the full JSON object and argument arrays rather than substituting empty strings for collections.

The frozen recipe argv/env reach both the released production-stack Helm chart and the distributed LeaderWorkerSet pods. The configuration and overrides enter the DevOps specification hash and provenance. Deployment validation remains automatically chained after the deploy stage; benchmarking is a separate explicit pipeline. No live GPU inference/benchmark is claimed by discovery or by expert handoff tests.

Current boundaries: canonical public Hugging Face config/weights metadata are still needed by profiling; NVFP4 GGUF repositories without their own config need a separate profiling path. Serving and API validation remain the existing text/chat recipe. Other modalities, recipe strategies beyond the supported renderer, composite/resident-memory estimators and arbitrary package/image installation remain explicit future work.

Sources: [upstream recipe maintenance](https://github.com/vllm-project/recipes), [recipe schema](https://recipes.vllm.ai/recipe.schema.json), [vLLM source registry](https://github.com/vllm-project/vllm/blob/v0.33.0/vllm/model_executor/models/registry.py), [GPU requirements](https://docs.vllm.ai/en/stable/getting_started/installation/gpu/), [vLLM image metadata](https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags/v0.33.0).
