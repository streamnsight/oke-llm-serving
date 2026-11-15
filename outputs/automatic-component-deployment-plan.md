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
- [ ] Pass focused Terraform/script tests and RMS-compatible package checks.
- [ ] Update the affected RMS source and validate component-only execution without creating, resizing or deleting GPU resources.
- [ ] Commit, integrate into local main and rebuild published-stack packages; record remaining limitations.
