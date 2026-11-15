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
- [ ] Validate Terraform, generated stacks, and RMS-compatible packaging without allocating GPUs or invoking live add-on changes.
- [ ] Commit changes, integrate into main, and rebuild packages; document live-validation limits.
