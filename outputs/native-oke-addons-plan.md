<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Native OKE add-on installation

## Phase 1 — requirements and lifecycle
- [x] Confirm native add-on APIs, dependencies, and preservation of existing installations.
- [x] Select NVIDIA and RDMA add-ons from the infrastructure configuration; exclude AMD and automatic GPU repair.

## Phase 2 — implementation
- [x] Enable missing OKE-managed add-ons before GPU allocation, including the debug path that skips GPUs.
- [x] Reuse existing settings and service-selected compatible versions; retain shared add-ons on stack destroy.
- [x] Include the implementation and explicit status in generated infrastructure ZIPs.

## Phase 3 — validation and delivery
- [x] Exercise missing, enabled, inactive, failed, and unsupported add-ons with strict offline fixtures.
- [x] Validate Terraform, generated stacks, and RMS-compatible packaging without allocating GPUs or invoking live add-on changes.
- [x] Commit changes, integrate into main, and rebuild packages; document live-validation limits.

## Validation record — 2026-11-14

- Passed 75 focused offline checks: 8 executable shell/CLI cases, 5 native add-on Terraform cases, 11 infrastructure cases, 24 allocation cases, 10 target lookup cases, 13 publisher cases and 4 tests against the rendered infrastructure ZIP.
- Validated discovery and both embedded downstream roots with RMS Terraform 1.5.7. Verified the actual rendered infrastructure archive, including saved-Plan/fresh-Apply archive creation.
- Rebuilt discovery and infrastructure packages, including the native add-on module and helper. No runtime Python, new root scripts or node_modules were introduced.
- Updated the existing Frankfurt component RMS stack's uploaded ZIP only. Downloaded it again and verified every source file, unchanged variables (`skip_gpu_allocation=true`) and unchanged job IDs. Preserved unrelated source edits and generated defaults.
- No live Apply, Destroy, DevOps pipeline, add-on installation, GPU allocation or capacity scan was executed. Live OKE installation, per-pool health policy and GPU/CUDA/RDMA checks remain unvalidated. Existing published discovery reports and object-storage bundles require a new discovery execution to regenerate.
