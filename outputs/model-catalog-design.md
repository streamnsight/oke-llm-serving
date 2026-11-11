# Curated model catalog and RMS packaging proposal

Research date: November 11, 2026. Proposal only; the discovery schema and runtime behavior have not changed.

## Recommendation

Use the Hugging Face Hub API to discover candidates and resolve canonical repositories, a release-specific vLLM compatibility manifest to filter them, and a small reviewed model-family map to prevent duplicate variants. Generate the RMS dropdown before packaging. Keep a custom model ID/URL input that goes through the same validation.

Interpretation to confirm: “System 1” means direct-response/non-thinking text models. If it instead means small language models, retain the same pipeline and change the selection policy. Model size and reasoning behavior are independent attributes. Hybrid thinking/non-thinking models should qualify only with a documented non-thinking serving configuration for the selected version.

## Sources and roles

| Source | Role | Limitation |
|---|---|---|
| Hugging Face Hub API | Repository identity, revisions, task, popularity, license, files and config | Downloads/trending are popularity signals, not suitability or quality guarantees |
| Publisher-owned HF repositories and collections | Canonical releases, family/size variants and model-card lineage | Needs a maintained publisher/family map; ownership is not inferred from a naming pattern alone |
| vLLM supported models and source at a pinned release | Architecture/backend/format support | Architecture support is evidence, not a successful GPU load/inference test |
| Arena text leaderboard | Human-preference comparison and optional reviewed nominations | Do not scrape it in the build hook; published terms restrict automated querying/extraction |
| Artificial Analysis documented Data API | Optional benchmark enrichment | Requires an API key and attribution; verify redistribution terms before bundling its data |

Primary sources: [HF API](https://huggingface.co/docs/hub/en/api), [HF model-card lineage](https://huggingface.co/docs/hub/en/model-cards#specifying-a-base-model), [vLLM model support](https://docs.vllm.ai/en/stable/models/supported_models/), [Arena text rankings](https://arena.ai/leaderboard/chat/text), [Arena terms](https://help.arena.ai/articles/5629909088-terms-of-use), [Artificial Analysis API](https://artificialanalysis.ai/data-api/docs).

A live HF downloads query returned GPT-2 and a GGUF repository alongside chat models. This confirms that text-generation plus popularity alone does not produce a suitable deployment menu. Arena/API leaderboard entries also need explicit mappings to exact HF releases and evaluation modes; a score for a hosted endpoint is not automatically a score for our checkpoint/settings.

## Selection policy

Start with public text-generation chat/instruct models. Exclude embedding/reranking, image/audio/video, adapter-only, training intermediate and duplicate mirror repositories. Prefer canonical publisher checkpoints. Use base_model/base_model_relation metadata where available, with explicit family overrides when missing. Do not collapse genuinely different parameter sizes, instruct releases or fine-tuned products into one model just because they share lineage.

Select across small, medium and large deployment tiers so frontier-sized models do not crowd single-GPU options out. Keep quality and popularity as separate fields; missing benchmark coverage must not mean rejection or zero quality. A proposed initial menu size is roughly 20–40 entries, with a cap per family.

Initially choose canonical safetensors checkpoints that our profiler can estimate. Excluding a quantization format from this first catalog does not imply vLLM cannot serve it. Likewise, our profiler's narrower architecture coverage must be recorded separately from vLLM support. Gated models cannot enter the ready-to-use dropdown until authentication is implemented in discovery/deployment.

Compare config.architectures against the supported architecture/backend inventory for the pinned vLLM release. Also record checkpoint dtype/quantization requirements, chat-template availability and model-specific launch flags. Use explicit supported/unsupported/unknown states. Do not enable trust_remote_code automatically. A Transformers-backend candidate needs its own validation; a native-architecture allowlist is a deliberate first-release scope, not the full extent of vLLM support.

A candidate can be metadata-checked without being GPU-tested. Store this distinction. A tested badge must identify the checkpoint SHA, engine image digest, GPU type, settings and inference check. Serving on the user's selected GPUs remains a later fit/topology/compatibility decision.

For non-thinking mode, inspect model-specific recipes rather than guessing from names. Qwen3 demonstrates a documented enable_thinking switch; it is not a universal parameter for every model. [vLLM reasoning configuration](https://docs.vllm.ai/en/stable/features/reasoning_outputs/)

## Packaging and RMS behavior

Proposed build flow:

1. Fetch a bounded candidate set from HF downloads/trending queries and reviewed publisher seeds.
2. Resolve IDs/revisions and fetch metadata/config; normalize families and apply scope policy.
3. Check pinned-engine compatibility and profiler coverage; optionally attach permitted benchmark evidence.
4. Produce a catalog JSON snapshot with source timestamps, ranks, license/gating, checkpoint SHA, support evidence and recipe references, plus a rejection report.
5. Generate schema.yaml dropdown choices from that exact snapshot; bundle both into the stack artifact.
6. Validate the Oracle schema, assert dropdown/catalog agreement, and test curated/custom input resolution before packaging.

A curl/jq shell hook is appropriate **in the packaging pipeline**. It does not invoke Terraform, and RMS itself retains native Terraform-only discovery. Building an RMS package does not require GPUs; GPU smoke checks can occur in a separate validation stage with explicit status recorded.

The form has a curated model selector with a “Custom model” option. That option reveals a separate ID/URL and revision field. HCL resolves either choice to one effective model/revision and applies the same scope/compatibility checks. Plain RMS enum values should be real model IDs; richer information belongs in catalog metadata/help rather than a fragile label-parsing scheme. [Oracle schema enums and conditional fields](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/terraformconfigresourcemanager_topic-schema.htm)

RMS does not fetch the external dropdown interactively. Refresh the snapshot through an explicit catalog-update job; ordinary package builds can reuse the checked-in reviewed snapshot. Source failures must not publish an empty dropdown or silently replace a known-good catalog. Catalog validation does not bypass execution-time model SHA, engine, context and GPU validation.

## Proposed implementation phases

- [ ] Confirm System 1 scope, initial vLLM release and catalog size/tier policy.
- [ ] Add catalog contract, publisher/family rules and pinned-engine support manifest.
- [ ] Implement the bounded HF refresh hook and rejection evidence.
- [ ] Generate the RMS schema and implement curated/custom HCL resolution.
- [ ] Validate deterministic generation, missing metadata/source failures, duplicate handling and custom IDs.
- [ ] Validate the RMS form; add GPU inference evidence as infrastructure becomes available.

SGLang can be added as a separate compatibility manifest later. Support by one engine must never be inferred from support by the other.

## Refinement: image selection and an optional advisor plugin

The engine image is selected by assessment and pinned afterward. Users do not need to select a fixed vLLM version before entering a model. Maintain a catalog of candidate released engine images with their architecture/backend/format support and relevant dependency/GPU constraints. Resolve model requirements against that catalog and the possible GPU configurations. An assessment can return several feasible model/image/GPU combinations; deployment receives one selected combination with an immutable image digest.

An arbitrary model ID does not necessarily need a model-specific recipe. Many new fine-tunes use an already-supported architecture and checkpoint format. Structured config and engine support evidence can establish a candidate automatically. Unstructured publisher instructions become an additional evidence source when needed. The transformers_version field is serialization provenance, not a minimum engine version. Model cards sometimes state genuine minimum versions; those need source attribution and release-specific verification.

An LLM can extract such instructions and investigate unknown cases. It cannot establish that missing kernels exist, that an unknown architecture fits our memory estimator, or that inference succeeds on a particular GPU merely by interpreting prose. Keep reviewed compatibility and runtime validation separate.

Recommended workflow:

1. User selects a catalog entry or custom ID. Native discovery returns model facts, GPU/entitlement/capacity observations and explicit missing information.
2. Deterministic checks select candidate engines/configurations or return requires_validation with reasons.
3. For unresolved cases, generate [the assessment prompt](model-compatibility-assessment-prompt.md). The user can run it with an assistant, or an advisor plugin can execute the same investigation step and return a structured artifact.
4. The user selects a proposed configuration. Resolve/verify the image digest and bind the specification to the model SHA, engine image, GPU topology and serving assumptions.
5. The deployment stack and DevOps pipeline allocate/install and perform load/inference tests. Record runtime validity only for the exact tested combination.

The whole workflow could be exposed through an assistant plugin: discover, assess, select configuration, submit/poll RMS jobs, and inspect DevOps validation results. Terraform retains infrastructure/state ownership. The advisor step is independently usable through a prompt, so the initial RMS flow does not require an LLM service or plugin installation.

Prefer keeping the LLM investigation in this explicit workflow step rather than executing it during Terraform plan refresh. This makes review, retries, evidence and caching visible. If a future automated service performs the investigation, key its artifact by model SHA, engine-catalog version and request configuration; validate the artifact before consuming it. The provider/host adapter and its authentication are not selected or implemented by this proposal.

Assessment evidence should distinguish:

- static compatibility: supported, unsupported or unknown, with engine-specific reasons;
- memory/layout: estimated, infeasible or unknown, independently of engine architecture support;
- review: not required, pending or completed, with source references;
- runtime test: not run, passed or failed, with exact environment and logs.

A missing model from the curated list is not proof that it is unsupported. A reviewed model is not automatically runtime-tested. Newest available engine is not automatically the best image for the user's GPUs or required integrations.

Implementation additions:

- [ ] Define candidate-engine catalog and deterministic version/image selection.
- [ ] Generate an assessment request/prompt for unresolved models and accept a validated result artifact.
- [ ] Add the optional plugin adapter after its host and authentication model are chosen.
- [ ] Bind assessment results to exact model/image/GPU/configuration identities and runtime evidence.

References: [vLLM model registry and runtime checks](https://docs.vllm.ai/en/stable/models/supported_models/), [vLLM Docker images](https://docs.vllm.ai/en/stable/deployment/docker/), [example publisher version instructions](https://huggingface.co/Qwen/Qwen3-8B), [Transformers config serialization](https://github.com/huggingface/transformers/blob/main/src/transformers/configuration_utils.py).
