<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Cache and routing compatibility

The user requested feature options limited to compatible model/runtime combinations, validation of manual selections, and investigation of ways to enable real KV-aware routing. Keep GPU capacity and hardware deployment choices independent of optional caching/routing features. Do not silently replace a requested KV-aware policy with approximate prefix routing.

## Phase 1: Evidence and design

- [x] Check the existing MP launcher and exact-image capability evidence from the MP investigation.
- [x] Inspect the pinned Production Stack router and current upstream issues. Version 0.1.14 uses the legacy in-process controller; MP is a different protocol. Its KV-aware path tokenizes `prompt` rather than chat messages. Therefore this integration cannot currently be offered as general KV-aware routing, even for a conventional model. Unknown compatibility must remain explicit.
- [x] Investigate event-based alternatives. Production Stack issue 1208 proposes MP event consumption and hybrid-group matching, but remains open. llm-d's current indexer documentation marks hybrid-aware scoring as work in progress. Dynamo documents GPU and CPU-tier event routing and hybrid-model recipes, but those are not validation of Qwen3.8-27B on A10 with our stack.
- [x] Share one capability assessment across generated model options, discovery reporting and deployment validation. Determine cache layout from structured architecture metadata, not model names. Model, image, cache mode, PP/host geometry, request API and router protocol are separate compatibility dimensions.

## Phase 2: Enforce the supported surface

- [x] Remove unavailable KV-aware choices from RMS controls and generated model schemas. Preserve a descriptive unavailable status in the report; preserve all unrelated capacity-backed deployment choices.
- [x] Stop discovery from automatically forcing the deprecated in-process connector for KV-aware requests. Reject incompatible explicit/frozen policies before ZIP publication and before deployment.
- [x] Exclude the current in-process adapter for hybrid/unknown layouts and unsupported host geometry. Keep eligible MP configurations subject to exact-image startup validation; do not label them runtime-validated.
- [x] Reject pipeline overrides that would bypass the frozen cache assessment. Preserve the existing early HMA check before loading weights.
- [x] Document a concrete enablement path and end-to-end acceptance checks for a future event-based router. This change does not migrate platforms or implement an unmerged upstream router.

## Phase 3: Validate and deliver

- [x] Demonstrate failing regressions for hidden options, immutable recipe provenance, topology/layout rejection, pipeline bypass and report rendering; then pass focused executable/Terraform tests.
- [x] Validate committed discovery, standalone model and generated model ZIPs, including Terraform 1.5.7 relocation checks. Verify actual generated schema enums and module dependencies.
- [ ] Commit the feature and validation record; merge according to the repository workflow after relevant validation. Rebuild packages after merging. A local package does not update old RMS/report ZIP sources.

No GPU allocations, pool changes, model redeployments or platform migrations are needed to validate these compatibility controls.

References: [Production Stack issue 1208](https://github.com/vllm-project/production-stack/issues/1208), [llm-d indexer](https://github.com/llm-d/llm-d/blob/main/docs/architecture/kv-management/kv-indexer.md), [Dynamo offload routing matrix](https://docs.nvidia.com/dynamo/knowledge-base/modular-components/router/offloading-support-matrix), [Dynamo hybrid recipe](https://docs.nvidia.com/dynamo/dev/recipes/qwen3-5-122b).

## Enablement path

The minimum complete KV-aware integration needs an engine that can reuse the selected model's cache, residency updates for the relevant GPU/CPU tiers, exact tokenization of chat/completion requests with the serving template, and a router that matches cache groups correctly. Hybrid full-attention plus recurrent-state groups must all be resumable at the credited prefix boundary. Missing/expired workers, eviction, restarts, event gaps and queue pressure must not produce false cache hits. CPU-tier support is separate from GPU-resident routing and requires an event-capable offload connector; the assessed LMCache 0.5.3 image does not establish that support.

The smallest upstream-aligned follow-up is Production Stack's proposed `kvevents` integration once a released image provides it, paired with a compatible MP image (CPU events were added in LMCache 0.5.6; later versions add chunk-size negotiation). Its current issue is a feature proposal, not released functionality to enable by setting a flag. Keep the present feature unavailable until a pinned implementation passes the tests below. A maintained upstream change could be evaluated separately before release, but would require an explicitly built/published image and ownership of that preview.

Dynamo is the strongest documented alternative to evaluate for hybrid-cache routing: its current stable matrix documents vLLM GPU and native CPU-offload events, and development recipes cover Qwen3.5 hybrid MoE with KV routing. It would introduce a different frontend/worker integration; this is not proof for Qwen3.8-27B on A10, nor proof that our LMCache MP CPU tier is visible. llm-d supports native event indexing, but its current architecture documentation still labels hybrid-aware scoring as work in progress. Neither is an automatic migration recommendation.

Acceptance for any candidate: run two replicas; confirm actual GPU/CPU cache store and reuse; repeat chat and completion requests and observe the selected worker and credited reusable tokens; compare cold/warm results; force eviction and replica replacement; verify stale entries disappear and queues still balance; cover TP and each PP layout separately; check multimodal/LoRA separately before offering them. Freeze model/image/router/connector/topology/API evidence and publish availability only for the tested capability scope. Do not infer one model name test grants every architecture, image or storage tier.

## Validation record

- The three focused regressions failed on baseline: unavailable features were absent from the report, RMS advertised KV-aware routing, and an unassessed KV-aware configuration passed pipeline input validation. Evidence: `/tmp/cache-routing-baseline.log`.
- Executable launcher, pipeline, report and pinned-chart regressions: 85 passed, none skipped (`/tmp/cache-routing-js-final.log`).
- Terraform: capability module 7 passed; model delivery/execution 48 passed; publisher 11 passed; report 17 passed; discovery root 21 passed; actual generated-model package 5 passed. Provider mocks use the repository's strict fake OCI CLI; these tests make no claim about a live GPU model.
- Archives built from committed runtime source `0e08028`: discovery and standalone model ZIPs passed archive/relocation/init/validate checks. Discovery plus embedded templates and the real generated hybrid-model ZIP passed Terraform 1.5.7 checks. The generated ZIP includes the new module, excludes unavailable enums and passes the independent model-root fixture. Evidence: `/tmp/cache-routing-archive-*.log`, `/tmp/cache-routing-generated-model*.log`.
- Exact router image CPU-only reproduction: `docker.io/lmcache/lmstack-router:v0.1.14@sha256:7107e6a17740478749ef28c812df48f405ccfab8d92f40372a50ef678b6c6b63`. Using its actual `/opt/venv/bin/python` and `KvawareRouter.route_request`, chat tokenized `""` and sent `[]` to the cache lookup, while a completion prompt produced tokens. No Hub/model/GPU work was performed. Both disposable probe Pods and the ConfigMap were removed. Evidence: `/tmp/cache-routing-router-probe-v2.log`. The initial system-Python probe could not import the package; no claim is based on it.
- Playwright browser validation: expanded a hardware option and its compatibility section; verified KV-aware unavailable, MP requiring image validation, hybrid in-process unsupported, and retained infrastructure/model launch links. Screenshot: `/tmp/cache-routing-browser/compatibility.png`. No application console errors; the fixture's missing favicon returned 404.
- No serving image, live workload, GPU allocation or RMS source was changed. Existing immutable report/model bundles require a new discovery run with updated source to receive the controls. MP completion and an event-based router remain separate follow-up implementation; this change makes their present compatibility limits explicit.
