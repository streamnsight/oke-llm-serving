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
- [x] Update the affected RMS source and validate the first inline automatic deployment without creating, resizing or deleting GPU resources.
- [x] Commit, leave the requested usable feature branch in the main workspace and rebuild stack packages; record remaining limitations.

## Validation evidence

- Focused platform Terraform cases: 15 passed; infrastructure template: 11 passed. Shared delivery: 3; inline rendering/guards: 6; model delivery/staging: 14. Publisher cases: 13 infrastructure and 7 model.
- Generated infrastructure and model ZIP checks passed, including configured child roots and a fresh Apply worker using a saved archive Plan. Discovery plus both embedded templates passed Terraform 1.5.7 initialization/validation.
- Executable inline/component regressions: 19 passed, one optional GNU-tar case skipped; exact UTF-8 bytes, shell expansion protection and prefixed chart metadata are covered.
- Montreal service accepted 51,200 decoded bytes and rejected 51,201. Native Helm inline values also passed actual deployment, as recorded below.
- The live RMS Plan for source patch `e491754` succeeded and leaves the retained GPU node pool unchanged. Only component/software metadata, a nonallocating capacity report refresh and automatic execution change. Existing stack inputs were preserved.

## Phase 4 — user feedback on workload failure and report storage

- [x] Make `fix/auto-bootstrap-components` usable directly in the main workspace, preserving unrelated user edits.
- [x] Put routine status/failure/readiness reports in DevOps logs; remove mandatory uploads and orphaned component reporting resources. Retain actual runtime inputs and useful benchmark downloads.
- [x] Inspect the failed workload’s exact script and add released-holder/control-character regressions and readable lock diagnostics, preserving active/foreign-holder/CAS protections. The actual failed Lease remains unconfirmed.
- [x] Exclude volatile allocation observations from automatic coordinator revisions and test unchanged-Apply behavior.
- [x] Validate the final configured infrastructure and model ZIPs locally.
- [ ] Revalidate the log-only/report-cleanup variant and actual workload Lease in a fresh RMS environment. Deferred because the user is destroying the stacks; no further live updates, pruning or retries will run.

The first live automatic coordinator completed successfully on 2026-11-15 at 06:46:14 UTC: all three component pipelines and all nine prepare/native Helm/finish stages succeeded. Inline values worked through actual chart deployment; LWS used the corrected exact `v1.0.0` tag. This precedes the requested stdout-report cleanup.

## Final local validation and operational boundary

- Full Node suite: 131 passed, 3 optional skips, 0 failures. Platform Terraform: 16 passed; shared delivery: 3; model delivery: 8; model storage: 7; infrastructure template: 11; publishers: 13 infrastructure and 7 model.
- Final configured archives: infrastructure 4/4 and model 3/3 Terraform cases, including fresh-worker saved-Plan archive creation. The committed-source discovery ZIP, including both templates, also passed Terraform 1.5.7 initialization/validation. All three release packages were rebuilt; no node_modules or local state is shipped.
- Routine failures no longer make Artifact Registry calls. Original failure codes survive secondary report/cleanup errors. Successful native benchmark JSON remains a deliberate downloadable artifact.
- The failed workload used the current lock script. Released empty/null/missing holders are covered; occupied holders ending in newlines are preserved exactly and displayed as escaped JSON. No actual Lease was unlocked or modified. The live Lease could not be established before the user began destroying the stacks, so its exact conflict cause is not claimed fixed.
- IAM membership, compartment and declared upload permission matched the failed model pipeline. Early policy propagation is plausible but not proven; permissions were not widened.
- The temporary read-only diagnostic was canceled at 07:00:00 UTC on 2026-11-15; its exact temporary stage and inline artifact were deleted and verified absent. No existing pipeline, project, Lease, node pool or GPU allocation was changed by that diagnostic. No obsolete software/report objects were manually pruned after the user announced destruction.

Implementation and local validation are complete on the requested feature branch. The remaining unchecked item is explicitly deferred live validation after teardown; this branch is not merged into main. User README/schema edits and local state/tfvars were preserved.
