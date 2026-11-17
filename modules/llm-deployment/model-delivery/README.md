<!--
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

The model stack consumes a frozen discovery specification and an existing cluster ID. It owns an independent DevOps project, private OKE deployment environment, logs, immutable source/results repositories, a private OCIR chart mirror, four explicit model pipelines and scoped pipeline IAM. Apply runs trusted namespace onboarding, model deployment and a separate validation pipeline, and waits for each to succeed. It creates no GPU pool or shared controller. The `model-delivery` module accepts these model-owned resource IDs from the stack's `model-project` foundation; it never takes ownership of infrastructure resources.

OCI Generic Artifact permissions apply to the model project's workload compartment: unsupported repository-ID policy conditions are deliberately not used. OCIR chart access is restricted to the model's exact repository name. Pool access is read-only in its selected compartment. Runtime identities have cluster-use permission and namespace-scoped Kubernetes RBAC, without cluster administration or GPU-pool management.

1. Deploy the required retained GPU infrastructure and shared controllers first. Open the model ZIP link produced by discovery, choose the existing cluster, and Apply. Native metadata lookup infers the runner network, a unique compatible managed pool/platform and its trusted onboarding pipeline; missing or ambiguous prerequisites fail with an actionable error. A retained same-shape pool can be in another AD; discovery AD constrains new allocation. This lookup does not promise free GPUs.
2. Apply first executes the trusted `<platform>-model-onboarding` pipeline with the exact model project, namespace, pool and complete pipeline-ID set. It verifies these fixed defaults before granting namespace-scoped Kubernetes RBAC. The model project cannot grant itself cluster administration.
3. Apply then executes model deployment: owned namespace/allocation/storage preflight, deterministic chart import, native OCI Helm stage, rollout/image/health/model identity validation. A separate validation execution follows. Any failure fails Apply. Settings remain visible pipeline parameters for independent reruns; namespace and local chart source/version are immutable boundaries. Small sources, specifications, Helm values and command specs are readable inline artifacts. Large runtime/chart inputs remain Registry files; no command decodes an encoded script payload.
4. Benchmarking stays manual. Independent validation and benchmarking take the same model lease. Each operation inlines only its required sources and reuses the existing model-config input rather than uploading duplicate scripts/configuration. Routine status, validation evidence and failure logs are printed in the DevOps deployment log. Benchmarking uses the official digest-pinned vLLM CPU client and `vllm bench serve`, with downloadable native JSON results in Generic Artifact Registry. Text benchmarking defaults to `openai-chat` (`/v1/chat/completions`); select `openai` for `/v1/completions`, or `unsupported` to disable text benchmarking for another modality that needs its own dataset/probe adapter. Override `BENCHMARK_BACKEND` when starting the manual pipeline, or set `benchmark_backend` in the model stack to retain the default. Health checks alone never claim successful inference.
5. Run the separate undeploy pipeline before destroying its definitions. Terraform Destroy then empties and deletes the owned software/results repositories, including historical artifact versions and benchmark exports. It preserves model weights/PVCs and retained GPU infrastructure. The undeploy pipeline's `CONFIRM_UNINSTALL` parameter defaults to `true`, so no confirmation override is needed. It removes only the owned Helm release. CRDs, existing model PVCs, namespace, GPU pool and shared controllers remain. A failed native stage retains its lease; deliberate recovery requires the expired previous execution to be terminal.

Automatic execution uses native `oci_devops_deployment` resources with success postconditions. Its revision covers effective model settings, immutable runtime/chart sources, pipeline delivery code, the trusted onboarding definition and actual selected pool. Capacity snapshots, add-on inventory and observed retained pool size do not trigger another deployment. An unchanged Apply reuses its completed execution records; run the standalone validation pipeline for a fresh health check. A meaningful change replaces the executions in order. Failed executions can be retried through Apply after inspecting their DevOps diagnostics and any retained lease. Terraform metadata destruction never substitutes for explicit undeploy.

`onboarding_arguments` contains ready-to-use OCI pipeline parameter values, including `grant`. `MODEL_PIPELINE_IDS` is a plain comma-separated list of exact OCIDs; structured JSON and quote escaping are avoided at the Managed Shell substitution boundary. The trusted onboarding script splits the list into a JSON array, then rejects empty, duplicate, malformed or excessive IDs before verifying their project and target boundary. Automatic execution and manual-rerun outputs use identical arguments; no encoded payload or runtime `eval` is involved.

The local chart supports single-host TP with packed replicas, and native multiprocessing TP within each host plus PP across LWS hosts. LWS host separation uses Kubernetes 1.33+ `matchLabelKeys`, scoped to each group; different groups may share spare GPU slots. Rolling updates request no extra serving GPUs; a single replica has update downtime. It preserves the frozen recipe argument array and environment, including parsers, quantization and KV settings, then appends the adapter-managed identity/geometry/context flags. Weight dtype is never inferred from KV dtype. Cross-host TP, Ray, disaggregated prefill/decode, externally provisioned LMCache MP companions and other execution strategies need explicit adapters. A recipe that needs an unprovisioned companion fails before installing a release. Advertising an RDMA device is a preflight check; NCCL/fabric performance still requires a real distributed run and benchmark.

The vLLM API frontend defaults to Python (`api_frontend=python`, pipeline parameter `VLLM_USE_RUST_FRONTEND=0`), even when a recipe opts into Rust. Select `api_frontend=rust`, or explicitly set the pipeline parameter to `1`, only after validating the chosen model's template and API compatibility. This deployment overlay changes that single environment key; the raw recipe, remaining environment, image/model digests, chat template and parser flags stay intact. Effective runtime configuration records the selected default. Frontend changes participate in generation/settings checks and trigger automatic deployment and validation.

Discovery continues to record and default to an immutable Hugging Face commit. For `direct_hf` serving, an expert can set `model_revision=main` or the pipeline's `MODEL_REVISION=main` to download the current branch instead. This changes no serving image or recipe flags. Validation reports `main` as a `mutable_ref`, not a resolved commit; future downloads can differ from discovery's assessed snapshot. Retained PVC and staged snapshots still require the matching 40-character commit. Other branch/tag names are not accepted.

Each direct-Hugging-Face pod reserves a full checkpoint workspace; packed replicas multiply the host disk requirement. Unknown checkpoint sizes allow pipeline creation but require an explicit expert workspace before execution. Existing PVCs must be Bound and annotated `oke-llm/model-revision` with the immutable commit. Multi-host allocations require ROX/RWX because the scheduler can choose different retained GPU hosts; ReadWriteOncePod cannot support multiple serving pods. Object Storage staging does not imply a serving mount: the CPU scratch PVC is never reused as a model PVC. Until a retained serving PVC is materialized, staged mode fails with an actionable message.

Optional CPU weight staging belongs to this model project, not the infrastructure stack. Direct Hub mode creates no weight bucket or stager. Object Storage mode requires an explicit validated stager image and complete pinned file allowlist; it produces a separate administrator bootstrap manifest for staging RBAC/workload identity/scratch storage. Its download pipeline is intentionally excluded from model-serving onboarding. No stager image, credentials or serving-volume materialization is invented. Retained weight buckets must be handled explicitly before destroying their Terraform owner.

For multiple replicas, the same release includes the upstream production-stack router with a literal selector for this model's leader endpoints. Its upstream chart archive and router image are explicitly pinned because chart 0.1.14 defaults to a mutable `latest` router tag. Prefix-aware routing approximates locality; it does not consume KV events or persist conversations. Responses API support depends on the chosen engine; this adapter provides no durable response/conversation store. Public ingress/authentication is a separate configuration: the default endpoint is a private ClusterIP service.

Sources: [LWS vLLM deployment](https://docs.vllm.ai/en/stable/deployment/frameworks/lws/), [production-stack chart](https://github.com/vllm-project/production-stack/tree/405a2fa79992754d31f754c31b1eabb7183a540e/helm), [vLLM benchmark CLI](https://docs.vllm.ai/en/stable/cli/bench/serve/), [OKE IAM and Kubernetes RBAC](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengaboutaccesscontrol.htm).

Validation and benchmark command specs reuse the deployment’s existing immutable `runtime/common.sh` and `runtime/config.json` inputs, with checksum verification. Smaller operation scripts remain readable inline. The complete raw command document is capped at 51,200 UTF-8 bytes and passed directly to the provider, whose SDK handles base64 transport encoding.

LMCache and routing are selected through `lmcache_mode` and `routing_mode` in the
model stack. `routing_mode=auto` preserves direct access for one replica and
prefix-aware routing for scale-out. Explicit `prefixaware` starts the router even
with one replica. `direct` rejects scale-out and a contradictory `router_enabled`.

`lmcache_mode=recipe` reads the optional frozen
`selection.serving_configuration.deployment_profile.lmcache` object (falling back
to the top-level serving configuration when that is the selected source). No
profile falls back to a recognized native LMCache connector in the recipe;
otherwise it is disabled, preserving existing bundles. For example:

```json
{
  "lmcache": {"mode":"mp","cpu_memory_gb":8,"chunk_size":256,"mamba_cache_mode":"align"},
  "routing": {"mode":"prefixaware"}
}
```

This object belongs under `serving_configuration.deployment_profile`; it extends
rather than rewrites the upstream recipe. `lmcache_mode=mp|inprocess|disabled`
and the optional `lmcache_cpu_memory_gb`, `lmcache_chunk_size` and
`lmcache_mamba_cache_mode` stack inputs override those recommendations. Routing
can be overridden with an explicit `direct|prefixaware|kvaware` selection. An
`auto` setting honors the frozen routing recommendation when present. Reject
unsupported profile values, conflicting raw cache flags/environment and unknown
companions before executing Helm. A declared `{"adapter":"lmcache_mp"}`
companion is fulfilled by the MP launcher; other companion contracts remain
unsupported.

The MP adapter starts `lmcache server` beside vLLM **inside the same container**,
sharing CUDA devices and IPC without another GPU request or host daemon. It
binds its request port to loopback and uses the external
`lmcache.integration.vllm.lmcache_mp_connector`. Startup refuses a missing or
incompatible connector; either process exiting stops the container. Each Pod
owns a disposable CPU cache, so replacement loses cache contents. There is no
disk/shared cache, cache persistence or conversation history in this adapter.
No runtime package installation or serving-image substitution is performed.

Use `lmcache_mode=inprocess` with `routing_mode=kvaware` for the pinned
production-stack router's controller protocol. The router starts its controller;
workers report unique Pod identities and Pod IPs. Pull, reply and heartbeat
ports are exposed through the router Service. This protocol is different from
the MP coordinator: `mp + kvaware` is rejected, not silently downgraded. Verify
the exact serving/router/LMCache protocol versions before enabling in-process
controller routing for a new recipe. A modern hybrid model's MP support does
not establish in-process support.

Both adapters currently require single-host TP. The cache budget is added to
the existing worker memory request/limit, once per Pod for MP and per TP rank for
in-process, plus process overhead. Changing TP on a manual pipeline execution
is rejected when caching is enabled; Apply must regenerate budgets and worker
ports. Scheduling still establishes available host RAM. For hybrid models,
select the assessed Mamba policy and validate negotiated block/chunk geometry;
the example above is a configuration shape, not a TP=4 correctness result.

Apply validates worker readiness and installed launcher configuration. Its result
explicitly labels cache store/retrieve evidence as requiring a manual cache
benchmark. A cache test must use repeated prefixes longer than the negotiated
block size and verify external store/retrieve counters and output correctness;
a generic random-prompt benchmark or `/health` response is insufficient. Routing
needs multiple actual replicas to establish backend selection. No GPU pool is
allocated, resized or recycled by these changes.

The existing manual benchmark pipeline accepts `BENCHMARK_PREFIX_TOKENS` (default
0) to generate requests sharing a prefix. Prefix + random input + output lengths
and template allowance must fit the context window. Choose a shared prefix above
the runtime's negotiated chunk/block size, then inspect native prefix and LMCache
store/retrieve counters separately. Repeated requests served from the GPU prefix
cache do not establish host-tier retrieval. This option does not clear live caches
or change the serving model automatically.

MP cache Prometheus metrics are exposed on the model Service's `cache-metrics`
port 9090 and scraped by the existing ServiceMonitor when monitoring is enabled.
Disabled caches keep the existing serving command, resources and Service ports.

For multi-host releases, the private HTTP Service is `<release>-http`; single-host releases retain `<release>`. LeaderWorkerSet owns the separate headless `<release>` Service and publishes leader/worker DNS before readiness, allowing distributed initialization. Validation and benchmarks select the HTTP Service from the effective host count; router endpoints are unchanged. Upgrading a previously failing multi-host release removes the old colliding HTTP Service so the LWS controller can create its headless Service.
