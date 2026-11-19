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
- [x] Run executable regressions, Terraform tests and generated archive checks, including Terraform 1.5.7 compatibility.
- [x] Validate router handoff in the exact router image on CPU-only workers.
- [x] Run Qwen/Qwen3-0.6B on existing GPU workers when available; require evidence of transfer, correct serving and a refreshed no-op Plan before claiming live validation.
- [x] Commit the feature and integrate benchmark/revision commits. Merge P/D only after the repository's required GPU end-to-end validation; build packages from committed source and record what remains unpublished.

## Efficiency and failure cases

Role rendering and placement checks are linear in role/pod count. Metrics use bounded snapshots and a bounded number of probe requests; no full benchmark starts automatically. Both roles own model weights and per-pod download workspace. Retained PVC access modes must support actual placement. A manually changed model/image/geometry requires reassessment rather than reusing stale metadata. Native handoff must work for chat and completions, including streaming, and must preserve primary failures and owned cleanup/lease semantics.

## Validation record

## Live GPU validation — 2026-11-19

- [x] User restored one retained A10 host; inspect actual Ready/allocatable capacity without changing the pool.
- [x] Run the exact pinned GPU image on one allocated device before loading weights: vLLM 0.32.0, NIXL 1.5.0, PyTorch 2.13.0+cu130 and driver 595.91.07 work on the A10. Connector resolves to NixlPullConnector. Save evidence and remove the exact owned diagnostic Pod.
- [x] Fetch fresh Qwen3-0.6B metadata with the repository profile module. Assessed SHA is c1899de289a04d12100db370d81485cdf75e47ca; estimated aggregate memory is 4.61 GiB per instance at context 4096/concurrency 1.
- [x] Create a separate model-only RMS stack from committed source with the retained pool, one prefill and one decode instance; inspect Plan for infrastructure/GPU-host mutations before Apply.
- [x] Complete trusted onboarding, native chart deployment and independent validation; resolve generic implementation failures in source and repackage rather than patch only live resources.
- [x] Run bounded quick benchmarking with paired cache workloads and report P/D transfer, recomputation, output comparison and missing-metric findings in logs.
- [x] Verify a refreshed no-op Plan, record observed findings, and satisfy the required end-to-end checks before merging.

Live private job/state/log evidence belongs under `/tmp/native-pd-live-20261119`, outside committed/packaged source. The image-check Pod was an owned temporary probe and has been removed; the retained GPU pool has not been changed by the agent.

Exact pinned Production Stack router digest `7107e6a17740478749ef28c812df48f405ccfab8d92f40372a50ef678b6c6b63` passed six actual CPU cases: chat/completions, streaming/nonstreaming, native metadata forwarding, and prefill errors. Missing metadata returned HTTP 200 and plain decode, confirming that readiness is insufficient. The reusable probe is `tests/native-pd-router-probe.py`; logs are `/tmp/native-pd-router-proof-success.log`. Exact owned probe resources were removed.

Nine observer regressions and seven executable launcher regressions pass. Coverage includes counter resets, missing/error evidence, expected locally computed tail tokens, all decoder replicas, whole-operation deadline with partial findings, stale mutable-ref layouts, alternate config bypass and literal argument preservation. Metadata/task/recipe/parallelism gates and both-role geometry have focused Terraform coverage: 13 capability, 33 profile, 13 publisher and 54 delivery/execution checks passed before final benchmark integration. Ordinary model runtime/chart regression suite: 46 passed, one optional upstream-chart integration skipped. Validation now preserves the owning operation's cleanup trap in a subshell so failed transfer checks cannot bypass its lease cleanup. Locked-provider and package checks are being completed after branch integration.

Comprehensive benchmarking and direct-Hub revision defaults were independently tested and merged to local `main`; P/D has integrated both. The benchmark passed the complete generated CPU Job/ConfigMap/tokenizer/client/log-streaming/cleanup flow against a synthetic HTTP Service. This proves client and lifecycle behavior, not GPU model performance or actual KV reuse. New direct-Hub stacks default to `main`; existing RMS saved values/uploads remain unchanged.

Final integration checks: 55 delivery/execution Terraform checks passed with locked OCI 9.13.0; 13 capability, 33 model-profile and 13 publisher checks passed. The combined JS runtime/chart/matrix suite has 54 passing checks and one optional upstream-chart check skipped (a stale temporary template copy initially failed the benchmark-default assertion; the corrected fixture's seven benchmark checks passed). The actual eligible discovery-generated model ZIP passes Terraform 1.5.7 validation and six root-level mocked-provider executions, including an explicit native P/D selection. Those executions validate configuration and delivery metadata, not a GPU engine. Main discovery/model packages were rebuilt after merging and both validate under Terraform 1.5.7.

The user restored one retained BM.GPU.A10.4 worker for live validation. The separate model-only Plan contains 50 managed creates, no deletes and no instance/node-pool/volume mutations. Trusted namespace onboarding, workload deployment, independent validation and RMS Apply all succeeded; refreshed state records each child execution as SUCCEEDED and confirms benchmarking was not started automatically. Both role pods are Ready with zero restarts on the existing host; TP=1 per role uses two of its four GPUs. No GPU resource has been allocated, resized or recycled by this work. The refreshed service Plan reports no changes: all 50 resources and outputs are no-op, including refreshed INLINE source serialization. The manual benchmark stage succeeded and removed its exact Job/ConfigMap. Required live checks now permit integration.

The actual orchestrated router probe reports `transfer_observed` and `no_failures_observed`: decode imported 2,628 prompt tokens through two transfers totaling 302,776,320 bytes, with zero locally recomputed prompt tokens in that counter window. Routed completions and chat succeeded; the greedy completion matched the direct-decode baseline. A separate direct native-handoff probe imported 929 tokens with no recomputation or transfer errors. These are real single-host A10 transfer results, not evidence about cross-host transport, other architectures, or performance gains. A mutable `main` startup config-source SHA is an observation, not proof of the exact subsequently loaded weights. Both role config observations resolved to the assessed SHA; known conflicting sources fail validation and missing observations stay unknown.

The [live benchmark record](benchmark-matrix-plan.md#live-gpurms-validation--2026-11-19) covers 128/128 successful measured chat requests at 1K/2K input lengths, unique/shared prefixes and concurrency 2. All four cells observed native transfer, zero decode-side prompt recomputation and no transfer errors; shared cases also observed prefix-cache hits. Mean/median/p90–p99 summaries streamed to DevOps Logging without result uploads. These cache-workload comparisons do not establish a P/D speedup over aggregated serving. The 32-sample p99 values are exploratory. The test deployment remains available for inspection; only diagnostic/client resources were cleaned.

Cold router/client image pulls temporarily caused DiskPressure on the small CPU worker roots (29.44 GiB). Only owned router pods were rescheduled; normal image cleanup recovered both workers, and all three nodes finished Ready with DiskPressure=False. No host repair, filesystem resizing, GPU recycling or unrelated workload changes were performed. Cold image space remains an operational constraint of these existing CPU workers.

Reference image for the first GPU probe: official `docker.io/vllm/vllm-openai@sha256:6ee133356d49ed24cee03dd0cda3d3980279a11c107ce3e752c89e76540f41c9` (v0.32.0 linux/amd64). Its small public registry config/history confirms `INSTALL_KV_CONNECTORS=true` and installation of `nixl==1.5.0`; the source Dockerfile's false default is overridden by release builds. This is image-build evidence, not proof of import/driver/transport correctness. No large GPU image layers were pulled onto CPU workers. Evidence is `/tmp/pd-image-v0.32.0-config.json` and the exact build commit's [connector requirements](https://raw.githubusercontent.com/vllm-project/vllm/5df63a7203cdb9328d824a27b682e77c7b9928be/requirements/kv_connectors.txt). The launcher also accepts CUDA-named NIXL distribution metadata; an eighth executable regression covers that diagnostic boundary.

## Larger TP=2 P/D validation — Qwen3-14B, 2026-11-19

- [x] Fetch a fresh profile at assessed commit `40c069824f4251a91eefaf281ebe4c544efd3e18`: 27.51 GiB/29.54 GB BF16 weights per role, context 4096 and concurrency 1.
- [x] Use committed runtime source and the same official vLLM 0.32.0/NIXL 1.5.0 image, main model revision, TP=2/PP=1 per role, one prefill and one decode on the existing four-A10 host.
- [x] Inspect the model-only RMS Plan: 50 creates, no GPU/instance/pool/volume changes. Explicitly undeploy only the earlier owned 0.6B test to release its GPUs.
- [x] Recover the tenancy dynamic-group object quota by reviewing an actual Destroy Plan and retiring only that now-unused 0.6B test stack's resources. Its 14 software artifact versions were pruned by the owned cleanup hook; all 50 resource deletions completed successfully.
- [x] Review the partial-state recovery Plan (five creates/45 no-ops, no hardware changes), complete trusted onboarding and confirm the actual Helm values and two-rank NCCL/NIXL startup in both roles.
- [x] Complete checkpoint loading and engine readiness, then verify routed inference, greedy output comparison and actual native KV handoff across the TP=2 groups.
- [x] Complete the separate validation execution and RMS Apply; run the bounded four-cell manual benchmark, verify owned cleanup/lease release, then inspect a refreshed no-op Plan.

Cold-start observations are separate from serving performance. Both full checkpoints downloaded successfully in approximately 468–471 seconds per role. The 16 GiB per-pod memory budget selected streaming/no-prefetch shard loading; the first roughly 4 GB shard took 67–72 seconds per role to load from the boot-volume filesystem. No resource/image/model patches were applied to bypass that behavior. The user deferred weight-delivery optimization, and no GPU host, pool, filesystem or unrelated workload was changed. Private evidence is under `/tmp/native-pd-qwen14b-20261119`.

The larger checkpoint reproduced a generic orchestration bug: both model Deployment templates omitted `progressDeadlineSeconds`, so Kubernetes' 600-second default marked the still-loading prefill rollout failed while the startup probe/readiness budget allowed 1,800 seconds. Both pods continued loading with zero restarts. The generic source fix now aligns the Deployment deadline with the bounded startup budget in both ordinary and P/D Deployments. Its owned recovery preserved the existing Pod templates, all three Pod UIDs, downloads and ownership/generation checks; no live-only field or status patch was used. The owned published validation report's shared model ZIP has also been refreshed from committed fixed source.

The existing TP=2 pods subsequently became Ready with zero restarts; controller progress conditions cleared naturally. A real routed probe passed chat/completions and greedy equality against direct decode. Decode imported 2,628 prompt tokens through four rank transfers totaling 432,537,600 bytes, with zero locally recomputed prompt tokens and no failed/expired/late transfers in the observed window. Both role config-source observations agreed. The fixed-source trusted onboarding, workload deployment, separate independent validation and RMS Apply all succeeded. The manual benchmark stage also succeeded; its exact Job/ConfigMap were removed and the model Lease released. All three nodes finished Ready with DiskPressure=False. The healthy four-GPU model and router remain running for inspection, with unchanged Pod UIDs and zero restarts.

The manual quick benchmark completed all 128 measured requests successfully in approximately 265 seconds: 32 requests per 1K/2K input and unique/warmed-shared-prefix cell, output 32 tokens, client concurrency 2. Actual inputs including chat formatting were 1,032/2,056 tokens. Median TTFT decreased from 1,484.5 to 1,192.3 ms for the 1K pair (19.69%) and from 2,103.5 to 1,377.6 ms for the 2K pair (34.51%). All four observation windows reported native TP=2 transfer, zero decode-side prompt recomputation and no transfer failures. Unique cases had zero prefix-cache hits; shared cases had approximately 72% aggregate hit ratios. Full mean/median/p90–p99 latency, throughput and transfer summaries streamed to DevOps Logging without result-artifact uploads.

These are paired cache-workload observations through the live router, not a cache-disabled comparison or a P/D-versus-combined performance claim. Engine counter windows include warmups; p99 is exploratory with 32 requests per cell. This validates the larger model's single-host handoff and caching behavior, not cross-host transport or arbitrary model/image compatibility. Private event summaries and raw evidence remain under `/tmp/native-pd-qwen14b-20261119`; the refreshed RMS Plan already shows all 50 resources and outputs unchanged.
