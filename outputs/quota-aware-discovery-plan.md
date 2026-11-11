<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

# Quota-aware discovery

## Phase 1 — scope and filtering
- [x] Add `only_shapes_with_limits` (default false) through discovery and regional modules.
- [x] Filter only confirmed zero-limit shapes; retain unknown mappings. Prioritize shape-matched headroom queries over unrelated GPU limits.

## Phase 2 — reporting
- [x] Report capacity, configured limits, and observed headroom separately per region/AD/shape, independent of model fit.
- [x] List shapes with positive capacity and headroom. When none qualify, suggest exact limit increases for shapes with capacity and a zero limit.
- [x] Preserve unknowns and quantity-validation caveats; do not label consumed headroom as a zero configured limit.

## Phase 3 — verification
- [x] Test broad/filtered modes, missing mappings, zero limits, exhausted headroom, capacity absence, and AD scoping with Terraform mocks.
- [x] Run formatting, validation, and relevant module/stack tests; document live-cloud validation boundary.

Implementation uses native Terraform. Default broad discovery preserves visibility for limit-increase recommendations; filtered mode cannot observe capacity of skipped shapes. Joins iterate over regional shape/limit observations; no additional cloud calls are added for reporting.

Validation: `terraform test` passed for accelerator-inventory (8), regional-capacity-scan (4), deployment-planner (12), and discovery (2): 26 tests total. Discovery `terraform validate`, scoped `terraform fmt -check`, and `git diff --check` passed. Tests exercise native provider mocks, not a fresh OCI/RMS job. No cloud reports or GPU allocations were created. Live OCI/RMS end-to-end validation remains pending.

Integration: the user requested consolidation into `main`. Quota-aware discovery is included alongside the serving workflow, research reports and repository documents. Local validation covers the combined tree; cloud/GPU/DevOps execution remains pending. The original feature branches remain available in Git history.
