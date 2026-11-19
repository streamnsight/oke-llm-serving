<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Benchmark matrix and log summaries

The user requests readable benchmark summaries in DevOps logs, removal of result uploads, matched unique/shared-prefix workloads and meaningful input lengths. They selected unique versus shared prefixes rather than a separate cache-disabled deployment. Keep one manual pipeline with a `quick|full` flag; this avoids duplicating lifecycle/IAM/lease behavior. Do not change serving flags, reset live caches or redeploy models to benchmark them.

## Phase 1: Workload and reporting design

- [x] Trace the native vLLM CPU client, pipeline parameters, Job lifecycle, output upload and existing tests.
- [x] Confirm the user's cache-comparison scope. Unique prompts reduce intended reuse; shared prefixes exercise warm reuse through the current router. Neither means prefix caching has been disabled. Native readiness/warmup requests are outside latency samples.
- [x] Implement a stdlib matrix planner/runner around the pinned native `vllm bench serve` client. Preserve exact tokenizer/model revision and existing API adapters. No runtime package installation or model-specific flags.
- [x] Quick: 64 requests per cell at two auto-selected input lengths (1K and up to 4K). Full: 512 requests per cell across 512/1K/2K/4K/8K/16K, bounded by deployed context. Keep requested output length 128 and concurrency fixed across matched cells; allow explicit lengths/sample/concurrency/time overrides.
- [x] Total input includes the shared prefix. Use a 75% shared prefix by default, a fresh run seed and different seeds across cases to reduce contamination. Record actual prompt/output lengths and warmup behavior. Respect context plus template allowance; reject oversized explicit workloads before Job creation.
- [x] Print mean, median and p90 through p99 for TTFT, time per output token, inter-token latency and end-to-end latency; include throughput, request success/failure counts, sample-size caveats and paired shared/unique comparisons. Never average percentiles across cells.
- [x] Read per-replica prefix-cache counters when available, with explicit unknown/reset handling. Counter changes cover the case including readiness/warmups and may include other client traffic; do not claim an isolated cache-off experiment.

## Phase 2: Pipeline and lifecycle

- [x] Stream case summaries to DevOps logs as they finish. Keep raw native JSON temporary in the client Job; emit only bounded aggregate JSON/text. Remove artifact upload, result-repository arguments and benchmark artifact-write IAM dependencies.
- [x] Preserve historical result repository ownership/cleanup for compatibility; this request stops producing exports and does not delete old results on upgrade. Repository retirement is separate from running benchmarks.
- [x] Keep CPU-only benchmark Jobs, bounded runtime, correct endpoint selection, current validated generation and the existing model lease. Extend the benchmark stage/lease budget for full mode without affecting deployment/validation timeouts.
- [x] Fail promptly when a Job fails; keep partial summaries and the primary exit status. Clean up only the execution's exact Job/ConfigMap and log follower.
- [x] Expose quick/full in the model stack schema and editable pipeline parameters. Changing manual benchmark settings must not redeploy the model.

## Phase 3: Validation and delivery

- [x] Add meaningful failing regressions for matrix/context math, equal-length cache cases, distributions/failures, summaries without uploads, endpoint selection, Job failure/cleanup and manual-only Terraform behavior.
- [x] Exercise the exact CPU image with a mock HTTP endpoint, including the real generated Job/ConfigMap, client download, streamed summaries, polling and automatic cleanup.
- [x] Run a bounded quick workload against a live GPU model when one is available. No GPU pool allocation, resize or recycling. Do not launch the full matrix automatically.
- [x] Run focused executable/Terraform checks and validate committed and generated RMS ZIPs, including Terraform 1.5.7 and the 51,200-byte inline command limit.
- [x] Commit source and build/check reviewable discovery, standalone model and generated model archives from committed source.
- [x] Integrate per repository workflow and rebuild packages after integration; parent agent owns this step. Existing RMS sources and immutable report bundles require a separate update.

Cost: request count is `input lengths × 2 cache profiles × samples`. Generation work scales with total input/output tokens; the planner prints nominal work before execution. Native dataset memory is O(samples × input length); up to twice the required candidates are generated to remove accidental duplicate prompts, so reject cases above a bounded client dataset budget. Each run has an overall deadline; large custom matrices may need fewer samples or separate executions. Quick p99 is exploratory; full mode still prints sample counts and the small number of observations in the upper 1%.


## Validation record — 2026-11-19

- Seven focused matrix regressions pass: quick/full/context bounds, matched content lengths and separate warmup, native flags/tokenizer revision, aggregate distributions/privacy, native warmup failure, P/D observer wiring and unavailable/reset counters.
- All 47 executable model-delivery regressions pass; the existing optional pinned-router chart test is skipped when its chart file is not supplied. Four focused benchmark Job/parameter regressions pass again after lifecycle changes.
- All 48 model-delivery Terraform tests pass using the strict fake OCI CLI, including unchanged automatic deployment revision when benchmark mode/backend changes.
- An actual mock-provider Apply (rather than an unknown-at-Plan expression) measured benchmark command content at 38,034 raw UTF-8 bytes / 50,712 wire-base64 bytes; validation at 14,058 / 18,744. Shared P/D observation code is reused as an immutable input instead of duplicated inline.
- Exact pinned `vllm-openai-cpu@sha256:827ef38187f9b52f2bb838695ef815ec5b65f4bf3e4c061b002b2b0a19cb0701` image proof passed in the retained cluster: four unique/shared cells at 32/64 content tokens, four measured requests per cell plus separate warmups, all successful. Actual HTTP prompt usage matched tokenized lengths (40/40 and 72/72 across pairs). Native mean/median/p90–p99 summaries printed; benchmark execution took about 89 seconds. These synthetic endpoint timings establish client/reporting behavior only.
- The unchanged outer `benchmark.sh` then passed with a separate owned CPU-only mock Pod/ClusterIP Service, exercising real ConfigMap creation, generated CPU Job, full tokenizer download, log following/reconnection, terminal polling and automatic exact Job/ConfigMap cleanup. The final source streamed summaries before completion and returned zero. All exact owned test resources were cleaned. Logs remain locally at `/tmp/benchmark-matrix-e2e/final-run.log` and `/tmp/benchmark-matrix-proof/final.log`.
- Exact-image testing caught Transformers 5.19 returning a BatchEncoding by default from `apply_chat_template`; the context guard now explicitly requests `return_dict=False`, with regressions covering that default and oversized actual templates. Native chat requests use `max_completion_tokens` and typed content blocks, handled by the synthetic endpoint. Cold image startup also demonstrated a transient `ContainerCreating` log error; the outer script now reconnects early-ended log streams while the Job remains active, tested both by regression and the real Job.
- Committed discovery archive and embedded roots validate with current Terraform; standalone model archive validates with Terraform 1.5.7. Eleven publisher tests built real generated archives from committed source; the selected model ZIP passes five generated-root tests plus Terraform 1.5.7 archive validation. No package contains state, tfvars, tests or development dependencies.
- GPU workers were initially unavailable; the user subsequently restored one retained A10 host. The integrated live GPU/RMS run is recorded below. The agent did not allocate, resize or recycle GPU infrastructure. Synthetic endpoint timings above remain client/lifecycle evidence only.
- Existing results repository definitions and historical exports are preserved. No new benchmark upload or artifact-write pipeline permission remains.

## Live GPU/RMS validation — 2026-11-19

The manual pipeline ran against Qwen3-0.6B with official vLLM 0.32.0 and the Production Stack 0.1.14 orchestrated router. One prefill and one decode instance each used one A10 on the user's retained host. The CPU-only benchmark Job ran the exact pinned client image, using `openai-chat`, concurrency 2, output 32 tokens, two content lengths and 32 measured requests per cell. Chat templating added eight input tokens equally to both profiles. One separate warmup per cell is outside latency samples. The matrix completed in 143.367 seconds with 128/128 measured requests successful. The outer pipeline removed its exact Job and ConfigMap without an artifact upload.

Time to first token (milliseconds):

| Content tokens | Profile | Mean | Median | p90 | p99 | Requests/s |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1,024 | Unique | 607.214 | 608.512 | 609.673 | 637.244 | 2.736 |
| 1,024 | Shared 768-token prefix | 260.275 | 262.051 | 263.014 | 285.330 | 5.202 |
| 2,048 | Unique | 1,086.462 | 1,085.564 | 1,087.192 | 1,222.291 | 1.641 |
| 2,048 | Shared 1,536-token prefix | 387.141 | 388.484 | 389.742 | 496.262 | 3.847 |

The live logs include mean, median and every p90–p99 for TTFT, TPOT, ITL and end-to-end latency, plus throughput, actual token lengths, cache counters and P/D findings. Shared-prefix median TTFT was 56.94% lower at 1K and 64.21% lower at 2K. Unique-profile prefix hits were zero; shared-profile aggregate hit ratios were 72.16% and 72.44%, including warmup and both role engines. All four cells reported native transfer with no failures/expired/late notifications, no reset/missing counters and zero decode-side locally computed prompt tokens. Prefix reuse and native P/D therefore worked together in this test.

This is a small single-host cache-workload comparison with caching enabled in both profiles, not an aggregated-versus-P/D comparison or a general speedup claim. With 32 samples per cell, p99 is exploratory. CPU image pulls briefly caused DiskPressure on the existing small worker roots; all nodes recovered without filesystem/GPU changes, and the serving pods stayed healthy during benchmarking. Detailed private evidence is under `/tmp/native-pd-live-20261119` and DevOps Logging; it is not packaged with source.
