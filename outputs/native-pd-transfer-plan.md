<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->

# Native prefill/decode deployment and evidence

## Scope and success criteria

Add an explicit aggregated/disaggregated serving mode using the existing Production Stack 0.1.14 orchestrated router and native vLLM NIXL transfer. Begin with text-only uniform-attention dense/MoE architectures, PP=1 and single-host TP per role; each role has the same TP and a separately configured replica count. Unknown architectures, hybrid cache/PP combinations, conflicting recipe connectors and unimplemented companions are unavailable with a reason. This is a versioned adapter restriction, not a model-name blacklist or proof that upstream cannot support other layouts.

Use ordinary Deployments for the first role pools; DisaggregatedSet is not needed for this topology. Preserve existing aggregated Deployment/LWS behavior. Account for prefill and decode GPU/workspace demand together, retain shared infrastructure, and never resize GPU pools for validation.

Serving readiness and transfer effectiveness are separate results. A response that succeeds through recomputation is usable serving with degraded/unverified P/D, not verified KV transfer. Log per-role transfer bytes/operations/failures, prompt-token sources and probe timing where exposed; absent/reset metrics are unknown, never zero or proof of transfer. Do not log prompts or generated text. Benchmark summaries must preserve this distinction.

## Phase 1 — evidence and design

- [x] Inspect current chart, recipe/profile contract, router and upstream NIXL documentation.
- [x] Delegate the outstanding comprehensive benchmark and revision-default fixes to isolated feature branches.
- [x] Inspect live worker availability without changing infrastructure: only two CPU workers are registered on 2026-11-19.
- [x] Reproduce the exact router native handoff and inspect connector metrics/image requirements.

## Phase 2 — configuration and deployment

- [x] Add metadata-based eligibility and generated-schema gating with explicit reasons.
- [x] Add downstream serving mode and prefill-replica controls; reject incompatible pipeline overrides before Helm.
- [x] Render separate role Deployments/services, role discovery and native NIXL transfer settings using pinned upstream images.
- [x] Include both pools in GPU/workspace sizing, readiness, teardown and monitoring.
- [x] Add role/image/connector startup checks and preserve ordinary serving behavior.

## Phase 3 — runtime findings and checks

- [x] Add bounded inference/metric observation with transfer, recomputation and unknown outcomes in logs, a total deadline and greedy-output comparison against direct decode with separate cache salts.
- [x] Integrate P/D observations with the comprehensive benchmark without a result-upload dependency.
- [ ] Run executable regressions, Terraform tests and generated archive checks, including Terraform 1.5.7 compatibility.
- [x] Validate router handoff in the exact router image on CPU-only workers.
- [ ] Run Qwen/Qwen3-0.6B on existing GPU workers when available; require evidence of transfer, correct serving and a refreshed no-op Plan before claiming live validation.
- [ ] Commit the feature and integrate benchmark/revision commits. Merge only after the repository's required end-to-end validation; build packages from committed source and record what remains unpublished.

## Efficiency and failure cases

Role rendering and placement checks are linear in role/pod count. Metrics use bounded snapshots and a bounded number of probe requests; no full benchmark starts automatically. Both roles own model weights and per-pod download workspace. Retained PVC access modes must support actual placement. A manually changed model/image/geometry requires reassessment rather than reusing stale metadata. Native handoff must work for chat and completions, including streaming, and must preserve primary failures and owned cleanup/lease semantics.

## Validation record

Exact pinned Production Stack router digest `7107e6a17740478749ef28c812df48f405ccfab8d92f40372a50ef678b6c6b63` passed six actual CPU cases: chat/completions, streaming/nonstreaming, native metadata forwarding, and prefill errors. Missing metadata returned HTTP 200 and plain decode, confirming that readiness is insufficient. The reusable probe is `tests/native-pd-router-probe.py`; logs are `/tmp/native-pd-router-proof-success.log`. Exact owned probe resources were removed.

Nine observer regressions and seven executable launcher regressions pass. Coverage includes counter resets, missing/error evidence, expected locally computed tail tokens, all decoder replicas, whole-operation deadline with partial findings, stale mutable-ref layouts, alternate config bypass and literal argument preservation. Metadata/task/recipe/parallelism gates and both-role geometry have focused Terraform coverage: 13 capability, 33 profile, 13 publisher and 54 delivery/execution checks passed before final benchmark integration. Ordinary model runtime/chart regression suite: 46 passed, one optional upstream-chart integration skipped. Validation now preserves the owning operation's cleanup trap in a subshell so failed transfer checks cannot bypass its lease cleanup. Locked-provider and package checks are being completed after branch integration.

Comprehensive benchmarking and direct-Hub revision defaults were independently tested and merged to local `main`; P/D has integrated both. The benchmark passed the complete generated CPU Job/ConfigMap/tokenizer/client/log-streaming/cleanup flow against a synthetic HTTP Service. This proves client and lifecycle behavior, not GPU model performance or actual KV reuse. New direct-Hub stacks default to `main`; existing RMS saved values/uploads remain unchanged.

Live GPU validation currently cannot run because the selected cluster has no registered GPU workers. No GPU resource has been allocated, resized or recycled. P/D remains a feature branch until relevant GPU end-to-end validation; CPU evidence must not be reported as proof of real KV transfer. A mutable `main` startup config-source SHA is an observation, not proof of the exact subsequently loaded weights. Known conflicting role config sources fail validation; missing observations stay unknown.
