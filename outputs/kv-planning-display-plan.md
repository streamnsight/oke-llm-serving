<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->

# Show generic cache planning scenarios

## Phase 1 — diagnose

- [x] Inspect the supplied report and estimator. The report assesses Inkling-2-Small, not the linked Inkling-2-Mini. Its 262,144-token / one-sequence scenario already includes 51.539607552 GB of all-layer KV planning; the main metric ignores that fallback.
- [x] Preserve the distinction between ordinary KV estimates, partial full-attention payloads, all-layer planning scenarios and weight-based cache allowances. No model-name conditions or runtime compatibility changes.

## Phase 2 — implement

- [x] Add a regression for the reported hidden number, plus precedence and unknown/allowance cases.
- [x] Show the existing generic fallback in the main cache metric with its basis and an explicit unvalidated label. Keep complete and partial estimates ahead of planning scenarios.

## Phase 3 — validate and integrate

- [x] Run focused report tests and browser-check the supplied report data on desktop/mobile, including the collapsed sizing assumptions.
- [x] Commit, integrate after validation and rebuild/check the discovery ZIP from committed main. Existing reports and RMS uploads require an explicit refresh.

Only report rendering changes. The 51.54 GB scenario treats all 48 text layers as full-context attention with BF16 KV at the selected workload; it does not model Inkling's local-attention savings, auxiliary state, or actual engine allocation. It is not an upper bound. The Mini variant also repeats layers, which requires separate cache-layout validation.

## Validation — 2026-11-21

- Regression reproduced before the fix (two assertions failed); final focused report suite: 35 passed. Complete/partial estimates keep precedence, missing values stay unknown, and weight-fraction or unfamiliar scenarios retain distinct allowance labels.
- Guarded report Terraform tests: 22 passed with the strict fake OCI CLI.
- Chromium rendered the supplied report data at 1440 × 1100 and 390 × 844. The cache metric showed 51.54 GB with its all-layer/unvalidated label; assumptions stayed collapsed and the mobile page had no horizontal overflow. Screenshots and private report evidence remain under `/tmp/inkling-discovery-20261121`.
- No estimator formulas, serving eligibility, GPU resources or published reports changed.
- Feature commit `3199cbe` was fast-forwarded into local main after validation. The rebuilt `/tmp/oke-serving-main-discovery.zip` passed actual archive checks with Terraform 1.5.7 and locked providers. Refresh the discovery stack upload and rerun discovery to publish the new metric.
