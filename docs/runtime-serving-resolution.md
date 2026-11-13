<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Runtime recipe/image discovery and expert configurations

Discovery reads the selected model's live vLLM Recipes JSON endpoint, including checkpoint aliases. The response identifies the upstream recipe repository, path and source SHA. The resolver reads that YAML at the supplied immutable source; if the JSON endpoint is absent it tries the model's canonical vLLM recipe path. There is no static model or engine catalog, catalog build step, or executable model-card prose.

`modules/serving-resolution` uses only HTTP-provider data and HCL (`yamldecode`, JSON and expressions). It extracts the matching checkpoint variant, base and variant arguments/environment, default-hardware overrides, selected optional features, upstream hardware labels and strategy evidence. It does not install packages or execute launch commands from the guide. Missing recipes, ambiguous variants, unresolved templates, custom-image requirements and conflicting managed flags are returned as issues requiring expert configuration. HTTP access/rate-limit failures fail the lookup rather than pretending a recipe is absent.

## Discovery assesses; deployment chooses

Discovery asks for a public model/revision and context/concurrency requirements, plus optional scan scope. It does not ask users to predict an image override, CPU platform, feature flags, dtype or runtime tuning. Its automatic policy prefers a stable source tag declaring the architecture, retains a stale nightly hint as evidence, and falls back to nightly when required. It also assesses a supporting nightly alternative and publishes image digests by CPU platform. Optional feature definitions are retained without activation.

Deployment offers `engine_channel = "recommended"` (default), `"stable"` or `"nightly"` among the assessed candidates. `engine_platform = "auto"` follows the selected GPU node CPU architecture and uses its assessed platform digest. Missing images/platforms fail rather than substituting an incompatible image. An unassessed version needs an explicit digest-pinned `engine_image` / `engine_version` and expert review. Recipe features such as `reasoning` and `tool_calling`, dtype, runtime allowance, margin, argv/env and expert topology belong here.

Deployment consumes the recorded evidence without looking up moving tags again. Source registration and image metadata are evidence, not a GPU inference test. An explicit variant `nightly_required` remains distinct from an old `min_vllm_version: nightly` hint. GitHub `/releases/latest` is not assumed to mean a stable tag.

For Flint reasoning/tools, set this in **deployment**:

```hcl
recipe_features = ["reasoning", "tool_calling"]
```

The recorded feature definitions supply the `glm47` reasoning/tool parsers and related flags. Unknown features and complex modes/companions need explicit review rather than silently omitted settings.

## One JSON handoff

```sh
mkdir -p work
terraform output -json deployment_inputs \
  > work/deployment-inputs.tfvars.json
```

This produces one object: `{"discovery": {...}}`. It contains the model profile, workload assumptions, assessment choices, recipe provenance/requirements/features and digest-pinned engine/platform candidates. Repeated raw regional inventory and per-choice copies of the shared engine are omitted. The separate full `discovery` report remains available for investigation.

For local Terraform, pass that file unchanged alongside target infrastructure and deployment choices:

```sh
terraform -chdir=templates/deployment plan \
  -var-file="$PWD/work/deployment-inputs.tfvars.json" \
  -var-file="$PWD/work/target.json"
```

For RMS, paste the chosen `deployment_handoffs[ID].inline_json` into **Discovery JSON**. Do not paste the entire report: each RMS variable is limited to 8192 bytes. The compact payload contains one frozen selection and preserves literal recipe placeholders. Select the existing cluster; images, known networking and CPU defaults are resolved automatically in preview mode. Larger payloads use authenticated Object Storage input. See [the compact handoff and preview guide](deployment-preview.md).

## Three distinct results

`discovery.serving_configuration` records the frozen model SHA, recipe source SHA/hash, variant/features/arguments/environment, engine source SHA, platform image digest and selection rationale. `resolved_requires_validation` means structured lookup succeeded, not that inference passed.

`assessment.candidates` remains the per-rank estimator's output. Dynamic candidates additionally distinguish an upstream hardware/TP recipe match from `undetermined_requires_expert`. A match requires the selected recipe hardware/platform, a verified upstream hardware label, a declared single-node TP strategy, its explicit TP value and PP=1. Upstream hardware evidence still does not equal runtime validation in this tenancy.

`assessment.sizing_options` lists expert alternatives only when their estimated host quantity has confirmed capacity and GPU headroom. `assessment.sizing_diagnostics` retains all other visible NVIDIA GPU sizing observations, including unknown quantities or unavailable hardware. Each option carries capacity/limit/headroom observations, image-platform compatibility and a configuration-undetermined label. Known estimates are estimated GPU/node counts for the stated aggregate payload budget; TP, PP, communication, per-rank balance and model-specific scratch are not inferred. Unknown payload sizing stays null. These are alternatives for expert assessment, not executable deployment recommendations.

For BF16 Flint, structured GQA full/sliding layer metadata permits a full-context KV-payload bound across every layer and all resident expert weights. At context 4096, concurrency four, BF16, 2 GiB runtime allowance and 20% margin, this is about 93.2 GiB aggregate. One 24 GB A10 is insufficient; the aggregate budget corresponds to an estimated minimum of five A10 GPUs under 90% utilization. This is not a mathematical lower bound on actual hardware requirements: conservative KV assumptions can overestimate payload, while per-rank overhead can increase it. It does not establish that five GPUs form a valid layout or that 8 A10s will run well. Expert TP/PP and a per-rank memory bound remain required. Quantized/GGUF resident-memory estimation is still unsupported. Hub file sizes are reported separately as checkpoint-download/storage bytes when known; they do not become a GPU-memory estimate.

`assessment.recipe_hardware_targets` identifies catalog shapes/platforms matching the upstream verified hardware labels, including targets absent from the current scan. When observed limits are zero it suggests a limit increase; missing shape observations mean investigate entitlement/capacity, not global unavailability. GB200 (Grace/ARM64) is not silently treated as an x86 B200 host. The engine platform must match the selected OKE image/node CPU. OCI allocates whole shape instances: an eight-GPU bare-metal node reserves all eight GPUs even if a selected model replica uses fewer.

## Expert handoff

Start with `templates/deployment/target.example.json`. For an undetermined option, add:

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

Set `selection_id` to the candidate or sizing-option ID in deployment. The stack refuses undetermined configurations without explicit expert settings and rechecks immutable model/image identity, CPU platform, rank VRAM, GPU count, allocation geometry, storage and fresh physical capacity/entitlement. Expert mode relaxes unsupported software/layout inference; it does not bypass infrastructure checks.

Package both stacks with `make package`; the discovery JSON is passed directly to deployment.

The frozen recipe argv/env reach both the released production-stack Helm chart and the distributed LeaderWorkerSet pods. The configuration and overrides enter the DevOps specification hash and provenance. Deployment validation remains automatically chained after the deploy stage; benchmarking is a separate explicit pipeline. No live GPU inference/benchmark is claimed by discovery or by expert handoff tests.

Current boundaries: canonical public Hugging Face config/weights metadata are still needed by profiling; NVFP4 GGUF repositories without their own config need a separate profiling path. Serving and API validation remain the existing text/chat recipe. Other modalities, recipe strategies beyond the supported renderer, composite/resident-memory estimators and arbitrary package/image installation remain explicit future work.

Sources: [upstream recipe maintenance](https://github.com/vllm-project/recipes), [recipe schema](https://recipes.vllm.ai/recipe.schema.json), [vLLM source registry](https://github.com/vllm-project/vllm/blob/v0.33.0/vllm/model_executor/models/registry.py), [GPU requirements](https://docs.vllm.ai/en/stable/getting_started/installation/gpu/), [vLLM image metadata](https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags/v0.33.0).

## Recipe JSON suggestions

Discovery additionally consumes the recipe site's hardware-specific JSON renderings. `assessment.suggestions` preserves each choice's own image digest, default flags/environment, adapted topology, memory assumptions and provenance. A missing dedicated estimator no longer suppresses these single-node suggestions. Deployment selects the nested configuration with `selection_id`; no expert flag is needed for the unchanged suggested workload. See [implementation details and remaining boundaries](recipe-derived-suggestions.md). Optional cache companion plans are retained as evidence, not automatically installed.
