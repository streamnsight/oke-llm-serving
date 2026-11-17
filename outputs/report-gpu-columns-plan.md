<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Discovery report GPU columns

## Phase 1 — layout and comparison

- [x] Order deployment summaries by GPUs needed per replica, hosts, limit/headroom, available GPUs.
- [x] Order regional rows by GPU sizing lower bound, GPUs per host, limit/headroom, AD capacity after the identity column.
- [x] Highlight insufficient numeric values in red, with an accessible explanation. Compare verified GPU limits/headroom against whole-host allocation; unknown values/units remain neutral. Keep equality sufficient and AD scopes unchanged.
- [x] Use existing sizing/capacity data only; no extra scans or changed deployment eligibility.

## Phase 2 — verify and deliver

- [x] Run focused report rendering and Terraform regressions.
- [x] Check desktop/mobile rendering and filtering in a real browser.
- [ ] Commit, integrate and rebuild the discovery ZIP; preserve unrelated workspace edits.

Validation: 22 report rendering tests and 17 Terraform report tests passed. An isolated Chrome session verified the new order and red computed colors at desktop (1440px) and mobile (390px), collapsed options, expansion and capacity filtering. The accessible shortage labels stay inside the table scroll container; neither viewport has page-level horizontal overflow. No OCI scans or cloud changes were performed.
