<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# LMCache capability checks and router startup

The exact serving image reports that LMCacheConnectorV1 lacks hybrid-memory-allocator support. Qwen's mixed full-attention/GDN cache cannot be promoted to a uniform cache; every replica fails after loading weights. The exact router image reaches application startup after its upstream startup probe's roughly 20-second budget; kubelet events confirm probe-driven restarts (not an established OOM).

Preserve the requested KV-aware policy. Do not silently downgrade routing, disable hybrid memory, install runtime packages or patch upstream model code. The operator must choose between a compatible classic-attention model, Qwen with the supported MP/prefix-aware path, or a separately implemented MP-aware routing integration.

1. [ ] Reproduce the installed connector's HMA capability failure without GPU execution. Add executable regressions and a generic early capability check based on frozen hybrid-cache metadata and the actual selected connector factory. Future HMA-capable connectors must pass; ordinary dense models must remain allowed.
2. [ ] Give the router a bounded startup window long enough for cold Python/controller initialization. Validate the exact router image with a disposable CPU-only fixture and the pinned upstream Helm chart. Do not alter readiness/liveness requirements or GPU resources.
3. [ ] Run focused runtime, Terraform and archive checks; commit, integrate tested source and update stack source without launching conflicting model operations. Recovery of the current deployment depends on the user's chosen supported model/cache/routing combination. Record evidence and unresolved runtime limits accurately.

Local work is prepared on `fix/lmcache-capability-and-router-startup`: frozen hybrid-cache metadata reaches the launcher, which checks the actual selected connector factory SupportsHMA capability before starting either cache or inference. Ordinary models skip the hybrid-only API check; future HMA-capable connectors pass. The router startup budget is bounded at roughly three minutes. Regressions fail on baseline (3 failures) and pass with the draft: capability/LMCache JS 11 passed, model-delivery Terraform 47 passed. No live workload configuration was changed.

The attempted isolated check inside the existing serving image could not run because the Pod had been removed by the time the command executed. Live logs and installed source inspection already establish the missing capability; no successful isolated image replay or CPU router startup validation is claimed. Archive/service validation and main integration are pending.

The user requested an explanation before choosing a recovery. Prefix caching and KV-aware routing are compatible features; current coupling to the legacy in-process LMCache controller is an integration limitation. A more general candidate is a router consuming native vLLM KV events (for example llm-d), leaving LMCache offload optional. That would be new integration work requiring its own plan and runtime validation. Do not silently switch model/cache/routing while this decision is open.
