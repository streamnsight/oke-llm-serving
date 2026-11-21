<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->

# Discovery UI: model facts, sizing, then locations

## Phase 1 — define

- [x] Inspect current report data, rendering, tests and memory semantics; preserve the active dashboard branch/worktree.
- [x] Choose GPU/shape/topology groups followed by region/AD availability. Keep different allocations, runtime configurations and P/D role counts separate.
- [x] Keep the planning payload distinct from topology-dependent total memory: show the sizing budget in the memory overview and total estimated memory per replica on each topology card, derived from its per-rank estimate and TP × PP.

## Phase 2 — implement

- [x] Promote humanized parameter count, layers, attention/KV heads, checkpoint dtype and declared maximum context. Collapse secondary metadata.
- [x] Collapse heuristic details and assumptions under one sizing disclosure; keep unknown estimates unknown.
- [x] Show GPU/topology allocation first, collapsed allocation/configuration details, then regional/AD capacity and scoped limit/headroom with exact launch links.
- [x] Default to fewer allocated GPUs, then fewer spare GPUs/hosts; retain filters, accessible serving tabs and each location's recommendation, presets and expiry.

## Phase 3 — validate and integrate

- [x] Focused executable regressions: cross-region grouping, distinct geometry/configuration, spare GPU counts, per-replica totals, partial/unknown memory, parameter formatting, P/D, scoped capacity and exact links.
- [x] Browser validation on desktop/mobile using rendered real report data plus a multi-region/multi-topology fixture; check expand/collapse, filters, sorting, keyboard tabs and launch URLs.
- [ ] Run report/root Terraform checks as needed; commit tested source, merge after end-to-end browser validation and rebuild/check the actual discovery archive from committed main.

This change does not alter model estimation, capacity eligibility, GPU resources or the serving runtime. Grouping is linear in option count; sorting is O(n log n). Location capacities are never summed across ADs. Published uploads remain at their existing source until explicitly refreshed.

## Validation record — 2026-11-20

- Node 24 full suite: 209 passed, 4 optional skips, 0 failures. Final focused report suite after a small packing-label correction: 34 passed.
- Guarded Terraform 1.9.8 tests: report module 22 passed; discovery root 21 passed. Strict fixture OCI CLI blocked unintended cloud calls.
- Headed Chromium: 1440 × 1100 desktop and 390 × 844 mobile. Real Qwen3-14B report data rendered correctly; a synthetic multi-region fixture grouped five location choices into two distinct topology cards. Six used GPUs / two replicas / six hosts / twelve allocated GPUs remained distinct from seven used GPUs / fourteen hosts / twenty-eight allocated GPUs.
- Verified closed sizing/allocation/configuration disclosures, expanded packing and location actions, exact source launch/download links, GPU/region/AD/no-match filters, allocation/capacity sorting, P/D role counts, keyboard tab focus and unsupported P/D explanations without launch actions. Mobile page width matched the 390px viewport; no page overflow. Only the preview server's unrelated favicon request returned 404.
- No live stack, GPU allocation or published report was changed. Browser evidence and private fixtures remain outside the repository under `/tmp/oke-sizing-ui-preview`.
