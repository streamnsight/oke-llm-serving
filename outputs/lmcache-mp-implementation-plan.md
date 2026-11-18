<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# LMCache multiprocess deployment

The user authorized implementing the recommended LMCache MP path while retaining prefix caching and investigating KV-aware routing. MP caching already has a local launcher, but it is opt-in and limited to single-host TP. Multi-host PP uses vLLM's multiprocessing executor, which is independent of LMCache MP. Discovery currently overrides the recipe with the legacy in-process connector when KV-aware routing is selected.

## Phase 1: Establish exact capabilities

- [x] Trace existing discovery, delivery, PP and cache contracts; preserve the requested routing policy.
- [x] Inspect upstream LMCache v0.5.3 and Production Stack source. MP's connector supports HMA; the current Production Stack router has no MP event consumer. Upstream issue 1208 tracks this as an open feature, including hybrid-group and chat-tokenization requirements.
- [x] Run an isolated preflight in the exact selected serving image without requesting GPUs or loading weights. Check actual hybrid-cache geometry requirements instead of assuming latest documentation matches this older image.
- [ ] Confirm the user's requested scope for the separate routing integration; continue independent MP work while awaiting the response.

## Phase 2: Complete MP integration

- [ ] Make MP the recommended cache path without silently changing KV-aware requests to prefix-aware routing.
- [ ] Select the required hybrid cache policy from structured architecture metadata. Preserve frozen recipe evidence and explicit compatible overrides.
- [ ] Configure MP object groups and negotiated block/chunk/batch geometry using the selected image's supported APIs and flags. No model-name tables, runtime package installs or model patches.
- [ ] Preserve process supervision, memory budgets, unique replica caches, and early actionable compatibility failures.
- [ ] Keep unsupported multi-host PP/cache layouts explicit; do not infer that vLLM's multiprocessing executor establishes LMCache compatibility.

## Phase 3: Verify and deliver

- [ ] Add failing executable and Terraform regressions for the identified gaps, then make them pass.
- [ ] Run focused launcher, rendered-chart, Terraform and committed-archive checks, including Terraform 1.5.7.
- [ ] Validate the exact runtime on existing retained hardware where the workload and routing combination is supported, without changing GPU infrastructure or overlapping a live deployment.
- [ ] Commit tested source; integrate only after the relevant end-to-end validation. Record separately what passed locally, in the image, in RMS and on GPUs. Rebuild packages after integration; existing report ZIPs remain immutable.

References: [LMCache MP guidance](https://docs.lmcache.ai/legacy/index.html), [hybrid recipe](https://docs.lmcache.ai/recipes/qwen3_5.html), [Production Stack MP routing issue](https://github.com/vllm-project/production-stack/issues/1208).

## Validation and decisions

The disposable CPU-only image check ran on an existing worker using the already cached `docker.io/vllm/vllm-openai@sha256:d392f621bb3e372ecc09f0b0cb88099afe9fa05d37a0450de45eeb8c12b6787e` image. It requested no GPUs, loaded no model weights and changed no retained resources. The actual vLLM factory reported `LMCacheMPConnector supports_hma=True` and `LMCacheConnectorV1 supports_hma=False`. Installed versions: vLLM `0.1.dev19754+g3a0914114`, LMCache `0.5.3`, Torch `2.13.0+cu130`. Both check Pods and both ConfigMaps were removed afterward. Evidence remains under `/tmp/lmcache-mp-image-check.log` and `/tmp/lmcache-mp-installed-source.json`, outside the source tree.

Installed source requires MP chunk size to be a multiple of the engine's block size and, in Mamba align mode, a scheduling batch budget in `[N, 2N)`. The server's object-group separation defaults to false. Latest LMCache documentation must not be applied blindly to this image: released `v0.5.7.post1` adds chunk-size negotiation and newer hybrid scheduling behavior, while this older image lacks them. An image update requires an explicit assessed override and runtime validation, not a hidden package upgrade or model-name constants.

The user asked for clarification rather than selecting a routing scope. Explained that MP provides KV offload/reuse in a separate process, prefix caching describes reuse of matching token prefixes, and KV-aware routing is a separate decision about which replica receives a request. Our current per-Pod cache is not shared across hosts. CPU offload adds retained reusable storage; it does not automatically enlarge active GPU context/concurrency or offload model weights. No serving configuration, routing policy, live stack, image or model workload has been changed on this branch. The implementation remains in progress while these architectural choices are clarified.
