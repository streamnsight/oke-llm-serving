<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Simplify discovery controls

Discovery always checks GPU limits, effective headroom and physical capacity in READY subscribed regions, including zero-limit shapes. Confirmed capacity with sufficient entitlement produces ranked deployment choices. Positive capacity needing higher limits stays an alternative without a deployment link. Ranking remains hardware fit then confirmed growth. Missing capacity/headroom never becomes confirmation.

1. [x] Remove discovery switches for headroom, zero-limit filtering, raw diagnostic dumps and GPU allocation. Keep the infrastructure-only allocation debug control editable downstream. Preserve user edits.
2. [x] Verify zero-limit capacity scans, exclusions, unchanged ranking, useful report explanations, generated infrastructure defaults and the simplified RMS form using mocked/offline tests. No cloud Apply, scans or GPU operations.
3. [ ] Validate the discovery ZIP and both embedded templates with Terraform 1.5.7, integrate the tested change into local main, and rebuild the package.

The detailed-diagnostics switch used to embed a second full raw model/engine/regional evidence tree. Remove that dump while retaining the report's model memory assumptions, configuration notes, per-AD limits and exclusion summaries automatically. Do not change native allocation admission checks or unrelated publication controls.

Validation so far:

- Mocked Terraform: root discovery/publication 12, planner 53, report 12, infrastructure publisher 12; all passed.
- CLI/DOM/RMS-schema Node tests: 23 passed, including zero-limit capacity with observed zero headroom, existing ranking and generated editable infrastructure defaults.
- The real report module rendered an offline page from saved 16-region inventory without provider/network calls. Browser local-file access was blocked by browser policy, so no browser preview is claimed; renderer behavior was checked with DOM tests.
- No cloud scans, Apply, pipeline execution or GPU changes.
