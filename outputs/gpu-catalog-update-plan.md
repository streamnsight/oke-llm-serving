<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

# GPU catalog completion

## Phase 1 — source review
- [x] Compare bare metal and VM GPU tables with the existing catalog.
- [x] Verify NVIDIA compute capabilities and identify AMD/null and memory-table inconsistencies.

## Phase 2 — catalog update
- [x] Add all missing shapes with GPU count, per-device decimal memory, CUDA capability and documented RDMA support.
- [x] Record sources and memory interpretation without broadening engine support.

## Phase 3 — verification
- [x] Check JSON and exact shape coverage against Oracle's tables.
- [x] Run planner tests, including rejection of newly catalogued architectures unsupported by current engines.
- [x] Commit this scoped change on its feature branch. Live GPU deployment is outside this catalog correction.
