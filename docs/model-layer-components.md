<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Model serving components and optional adapters

This table separates dependencies from optional deployment approaches. A recipe command is evidence for an exact model/image/configuration, not a complete cluster-platform specification. Unknown integrations remain visible and require validation; they are never executed as unreviewed shell text.

| Part | Shared infrastructure owner | Model owner and selection rule |
| --- | --- | --- |
| GPU/runtime/network support | Retained pools, OKE-managed GPU/RDMA add-ons, supported fabric and images | Device requests, allocation selector, engine flags and transport settings; no pool resizing/cycling |
| Workload orchestration | LWS/DAS or another explicitly selected controller/API | Deployment/LWS/DAS/Ray instances for the chosen executor; one workload manager per instance |
| vLLM Production Stack operator | Optional controller/CRDs, if this adapter is selected | Its namespaced runtime/router/cache CRs; it is not required for ordinary Helm serving |
| Monitoring and scaling | Reused/managed Prometheus/operator and optional KEDA | Model monitors, rules, ScaledObjects and measured thresholds within retained GPU slots |
| Engine routing | Optional shared Gateway API/controller/inference APIs | A model router or pool/EPP/routes; avoid stacking multiple endpoint schedulers accidentally |
| LMCache | Only the deliberately shared controller/server/backend and placement prerequisites | Exact connector, compatible image, tiers, budgets, per-model identity and workers |
| Weight distribution | Optional retained model-data bucket and CPU staging adapter | Pinned full snapshot, local/PVC materialization, startup ordering and read-only credentials |
| Responses/conversation service | Shared gateway/database when serving several models | Model backend registration, routes and policy; a dedicated gateway can instead be model-scoped |

## Workload manager choices

Native workloads/Helm are sufficient for a single host. Distributed layouts can use LWS/DAS or another selected integration. The current model adapter focuses on native vLLM multiprocessing with TP within a host and PP across hosts; other execution layouts require their own tested adapter.

Production Stack documents Helm, its operator and Gateway Inference Extension as separate deployment paths. The operator currently defines `VLLMRuntime`, `VLLMRouter`, `CacheServer` and `LoraAdapter`; their controller/CRDs are shared infrastructure, while their instances are model resources. Do not install an operator simply because the engine is vLLM, or let Helm and an operator own the same workload. [Deployment options](https://docs.vllm.ai/projects/production-stack/en/latest/deployment/), [operator definitions](https://raw.githubusercontent.com/vllm-project/production-stack/main/operator/config/default.yaml)

## Routing is not conversation storage

For one replica, a Service can be enough. Multiple replicas can use a model-owned Production Stack router or a shared gateway with model-specific routing resources. Current Production Stack documentation shows the Gateway path as **agentgateway → HTTPRoute/InferencePool → llm-d Router EPP → vLLM**; that is not a claim every Helm installation uses llm-d. [Current Gateway integration](https://docs.vllm.ai/projects/production-stack/en/latest/deployment/gateway-inference-extension.html)

Routing capabilities need precise labels:

| Routing behavior | What it provides | What else it needs |
| --- | --- | --- |
| Round robin/load routing | Distributes requests | Model identity, health and concurrency policy |
| Session affinity | Reuses the same endpoint where possible | Stable session identity and enabled engine prefix cache |
| Approximate prefix routing | Estimates likely cache locality | Compatible tokenizer/prompt formatting and routing configuration |
| Event-driven KV routing | Tracks resident prefix blocks | Engine KV events, compatible indexing/rendering and endpoint discovery |
| P/D routing | Coordinates prefill/decode roles | Explicit transfer connector, topology and readiness contracts |

LiteLLM documents pod affinity without inspecting actual cache contents. llm-d precise routing consumes KV events and exact prompt rendering/tokenization. Neither mechanism supplies durable conversation history. [LiteLLM affinity](https://docs.litellm.ai/docs/proxy/cache_aware_routing), [llm-d precise routing](https://llm-d.ai/docs/well-lit-paths/foundations/precise-prefix-cache-routing)

## LMCache is a family of configurations

LMCache is optional. Host RAM offload consumes memory alongside the engine; local disk needs a sized/mounted tier; remote sharing needs a specific backend, credentials, capacity and latency policy. Multiprocess deployment can require GPU access, colocation and compatible IPC/CDI configuration, so its server is not necessarily a generic workload on an unrelated CPU pool. Redis is one possible backend, not a universal prerequisite. Offload, remote sharing and prefill/decode transfer are separate capabilities. [Storage backends](https://docs.lmcache.ai/kv_cache/storage_backends/index.html), [multiprocess deployment](https://docs.lmcache.ai/mp/deployment.html)

Freeze the exact engine/LMCache/image/runtime/connector/model/layout/backend tuple. LMCache distinguishes runtime ABI, connector loading and model/feature validation; an import or version comparison alone proves none of the cache correctness/performance properties. Cache identity must separate incompatible model revisions, dtype/layout, adapters and tenant policy. Published example memory amounts are not sizing recommendations for every OCI shape. [Compatibility contract](https://docs.lmcache.ai/getting_started/compatibility.html)

The current model adapter does not claim arbitrary LMCache tiers or remote backends are implemented. Required recipe companions must have a typed supported adapter and resource/placement plan before deployment. Merely preserving their upstream JSON does not deploy them.

## Five different kinds of state

| State | Purpose | Retention/ownership |
| --- | --- | --- |
| Model weights/configuration | Immutable inference input | Pinned snapshot; optional retained model data |
| KV tensors/prefix cache | Avoid repeated inference computation | Evictable, layout-specific engine/cache state |
| Response/semantic cache | Reuse a previous answer | Separate correctness, freshness and isolation policy |
| Conversation history | Reconstruct prior user/assistant/tool turns | Durable service/database with deletion, TTL and access policy |
| Long-term semantic memory | Recall selected information across conversations | Optional retrieval/summarization service, not automatic history retention |

KV eviction must not delete conversation history. Keeping history does not reserve KV tensors. A conversation identifier or sticky session header does not, by itself, implement either storage contract.

Expose API capability levels separately: stateless Responses, response-ID chaining, restart/replica-safe durable state, Conversations API operations, and optional long-term memory. Current reviewed vLLM source keeps response/message/event dictionaries in the API-server process and warns about retention. Its request schema includes `previous_response_id` and vLLM `session_id`; that does not establish a durable Conversations service. Exact pinned-image behavior still needs testing. [vLLM response store](https://raw.githubusercontent.com/vllm-project/vllm/main/vllm/entrypoints/openai/responses/serving.py), [request schema](https://raw.githubusercontent.com/vllm-project/vllm/main/vllm/entrypoints/openai/responses/protocol.py)

Possible stateful API adapters include:

- **LiteLLM:** Responses bridging/chaining plus gateway policy features; its documented session continuity requires configured backing storage. Verify requested Conversations operations separately. [Responses](https://docs.litellm.ai/docs/response_api)
- **vLLM Semantic Router:** documents a Responses state service, but current and versioned backend documentation differ. Pin and test the chosen release rather than assuming every Redis configuration is supported. [Current service configuration](https://vllm-semantic-router.com/docs/tutorials/global/api-and-observability)
- **OGX, formerly Llama Stack:** documents Responses, Conversations and configurable SQL-backed response persistence. It is a broader application server, with a published list of remaining conformance differences. [API coverage](https://ogx-ai.github.io/docs/api-openai), [persistence configuration](https://ogx-ai.github.io/docs/providers/responses/inline_builtin), [conformance](https://ogx-ai.github.io/docs/api-openai/conformance)

These are options for explicit integration, not default installed components or a promise that all APIs/modalities are equivalent. A shared conversation database survives ordinary model retirement. Model-specific rows, tenant isolation, retention/deletion, backup, replica consistency and credential references need an explicit service contract. Do not silently deploy a per-model SQLite file and describe it as highly available multi-replica conversation memory.

## Validation boundaries

Before GPU testing, validate bundle defaults and closure, pipeline creation, namespace/RBAC onboarding, Helm rendering/admission dry runs, CPU routing with synthetic backends, storage/authentication adapters, ownership and retire/revoke behavior. Durable conversation state can be tested across gateway restart/replicas without a GPU engine.

GPU engine loading, multimodal payloads, exact parser/tool behavior, cross-process cache correctness, packing/placement, P/D transfers, NCCL/NIXL/RDMA and benchmarking remain environment-specific tests. No mocked test or successfully created DevOps pipeline establishes those properties.
