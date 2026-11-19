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
- [ ] Exercise the exact CPU image with a mock HTTP endpoint, then a bounded quick workload against the existing live replicas. No GPU pool allocation, resize or recycling. Do not launch the full matrix automatically.
- [ ] Run focused executable/Terraform checks and validate committed and generated RMS ZIPs, including Terraform 1.5.7 and the 51,200-byte inline command limit.
- [ ] Commit validated source, integrate per repository workflow and rebuild packages. Record exactly what is tested locally, in the image and live; existing RMS sources and immutable report bundles require a separate update.

Cost: request count is `input lengths × 2 cache profiles × samples`. Generation work scales with total input/output tokens; the planner prints nominal work before execution. Native dataset memory is O(samples × input length); up to twice the required candidates are generated to remove accidental duplicate prompts, so reject cases above a bounded client dataset budget. Each run has an overall deadline; large custom matrices may need fewer samples or separate executions. Quick p99 is exploratory; full mode still prints sample counts and the small number of observations in the upper 1%.


## Validation record — 2026-11-19

- Seven focused matrix regressions pass: quick/full/context bounds, matched content lengths and separate warmup, native flags/tokenizer revision, aggregate distributions/privacy, native warmup failure, P/D observer wiring and unavailable/reset counters.
- All 47 executable model-delivery regressions pass; the existing optional pinned-router chart test is skipped when its chart file is not supplied. Four focused benchmark Job/parameter regressions pass again after lifecycle changes.
- All 48 model-delivery Terraform tests pass using the strict fake OCI CLI, including unchanged automatic deployment revision when benchmark mode/backend changes.
- An actual mock-provider Apply (rather than an unknown-at-Plan expression) measured benchmark command content at 37,716 raw UTF-8 bytes / 50,288 wire-base64 bytes; validation at 14,058 / 18,744. Shared P/D observation code is reused as an immutable input instead of duplicated inline.
- Exact pinned CPU-image proof is running in an owned CPU-only Job against a local synthetic HTTP endpoint. The first proof caught Transformers 5.19 returning a BatchEncoding by default from `apply_chat_template`; the context guard now explicitly requests `return_dict=False`, with a regression exercising that default. The native CLI uses `max_completion_tokens` for chat, accounted for by the synthetic endpoint.
- Live model benchmarking cannot currently run: both retained workers are CPU-only and no GPU workers/model endpoint are present. No GPU allocation, resize, recycling or serving deployment is performed by this work. GPU runtime validation and RMS service validation remain outstanding; do not claim the synthetic endpoint proves model/cache/P/D performance.
- Existing results repository definitions and historical exports are preserved. No new benchmark upload or artifact-write pipeline permission remains.
