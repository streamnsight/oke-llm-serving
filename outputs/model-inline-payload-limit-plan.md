<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Model inline command payload limit

## Phase 1 — reproduce
- [x] Measure complete validation/benchmark YAML and encoded API fields.
- [x] Reproduce the missing transport-size guard locally; compare with the earlier GENERIC_FILE update probe without generalizing across artifact types or API operations.

## Phase 2 — correct delivery
- [x] Keep small scripts readable inline and reuse the existing common.sh runtime input; create no duplicate script uploads or status-report artifacts.
- [x] Guard 51,200 raw UTF-8 bytes and pass raw text to the pinned OCI provider, whose Go SDK performs base64 transport encoding. Keep encoded length diagnostic only.
- [x] Update regression coverage and repository guidance.

## Phase 3 — validate and deliver
- [x] Pass focused tests, configured child ZIP checks and Terraform 1.5.7 package validation.
- [x] Commit the SDK transport correction on the usable fix branch; include it in the automatic-model execution packages.

Read-only RMS lookup identified the exact failed job by its request ID. A model-specific repaired source ZIP preserved all stack inputs/defaults. Its initial metadata-only RMS Plan/Apply succeeded, creating both previously failing artifacts and their stages without GPU changes. The real Plan also exposed the raw/encoded field mismatch, leading to the final SDK transport correction. Automatic execution and its live checks are tracked separately in [the model execution plan](model-automatic-execution-plan.md). Existing published Object Storage bundles are not changed by a local rebuild.

## Evidence

- Before: validation 39,441 decoded bytes / 52,588 encoded characters; benchmark 45,044 / 60,060. The raw content fits the service content limit, but manually encoded Terraform input was encoded a second time by the Go SDK, inflating Create requests. Provider 9.13.0 uses a Go byte slice for this field and returns raw text on refresh.
- After: validation 12,996 decoded bytes / 17,328 encoded characters; benchmark 18,599 / 24,800 (mock model fixture). Real stack bindings add small metadata differences; both sizes are guarded.
- Existing deployment uploads already include `common.sh`. Operation inputs now reuse its exact path/version plus the existing config, and the actual rendered checksum steps verified all 7 validation / 8 benchmark files after local materialization. No additional script resources or report uploads were introduced.
- Focused checks: inline renderer 9, model delivery 8, shared delivery 3, model storage 7, platform 16, model publisher 7, infrastructure publisher 13; all passed. Exact-byte heredoc execution passed. Configured model ZIP 3 and infrastructure ZIP 4 mocked cases passed, including a saved-Plan/fresh-Apply worker archive check.
- The current RMS source matches the committed baseline for all three changed production files, and its latest failed job matches request ID `53f60784ecba5ce984bf2dc418921802`.

- The final tests assert exact raw provider values, including a valid 51,200-byte content boundary with a longer SDK wire representation. Mock tests cannot prove SDK serialization; verify the live refreshed Plan has no encoding-only changes.
