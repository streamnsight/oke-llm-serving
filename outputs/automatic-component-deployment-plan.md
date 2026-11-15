<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Automatic component deployment on Apply

## Phase 1 — execution lifecycle
- [x] Confirm the native deployment resource waits for terminal success and does not uninstall components on Destroy.
- [x] Define prerequisites and stable deployment triggers, including IAM propagation, failed-run retries and unchanged Applies.

## Phase 2 — implementation
- [x] Start the coordinator from Terraform after all component stages, artifacts and IAM are ready.
- [x] Expose execution status and make a failed component/validation fail Apply, preserving GPU allocation and explicit undeploy flows.
- [x] Update stack outputs, documentation and regression coverage.

## Phase 3 — validation and delivery
- [x] Pass focused Terraform/script tests and RMS-compatible package checks.
- [ ] Update the affected RMS source and validate component-only execution without creating, resizing or deleting GPU resources.
- [ ] Commit, integrate into local main and rebuild published-stack packages; record remaining limitations.

## Validation evidence

- Focused platform Terraform cases: 15 passed; infrastructure template: 11 passed. Shared delivery: 3; inline rendering/guards: 6; model delivery/staging: 14. Publisher cases: 13 infrastructure and 7 model.
- Generated infrastructure and model ZIP checks passed, including configured child roots and a fresh Apply worker using a saved archive Plan. Discovery plus both embedded templates passed Terraform 1.5.7 initialization/validation.
- Executable inline/component regressions: 19 passed, one optional GNU-tar case skipped; exact UTF-8 bytes, shell expansion protection and prefixed chart metadata are covered.
- Montreal service accepted 51,200 decoded bytes and rejected 51,201. API metadata accepted native Helm with inline values; runtime validation is pending below.
- The live RMS Plan for source patch `e491754` succeeded and leaves the retained GPU node pool unchanged. Only component/software metadata, a nonallocating capacity report refresh and automatic execution change. Existing stack inputs were preserved.
