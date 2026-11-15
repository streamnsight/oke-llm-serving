<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Model inline command payload limit

## Phase 1 — reproduce
- [x] Measure complete validation/benchmark YAML and encoded API fields.
- [x] Reproduce the missing transport-size guard locally; compare with the earlier GENERIC_FILE update probe without generalizing across artifact types or API operations.

## Phase 2 — correct delivery
- [x] Keep small scripts readable inline and reuse the existing common.sh runtime input; create no duplicate script uploads or status-report artifacts.
- [x] Enforce a conservative 51,200-character encoded field budget before submission, alongside decoded UTF-8 accounting, for command specs and Helm values.
- [x] Update regression coverage and repository guidance.

## Phase 3 — validate and deliver
- [ ] Pass focused tests, configured child ZIP checks and Terraform 1.5.7 package validation.
- [ ] Commit on the usable fix branch and rebuild the discovery/model/infrastructure packages.

Validation is local: no GPU allocation, pipeline execution or resource Apply is needed. Read-only RMS lookup identified the exact failed job by its supplied request ID. A model-specific repaired source ZIP will preserve all of that stack’s inputs/defaults; existing published Object Storage bundles are not changed by local packaging.

## Evidence

- Before: validation 39,441 decoded bytes / 52,588 encoded characters; benchmark 45,044 / 60,060. Both pass the old decoded-only guard and exceed the conservative encoded field budget. The new failing regressions reproduced this locally before the fix.
- After: validation 12,996 decoded bytes / 17,328 encoded characters; benchmark 18,599 / 24,800 (mock model fixture). Real stack bindings add small metadata differences; both sizes are guarded.
- Existing deployment uploads already include `common.sh`. Operation inputs now reuse its exact path/version plus the existing config, and the actual rendered checksum steps verified all 7 validation / 8 benchmark files after local materialization. No additional script resources or report uploads were introduced.
- Focused checks: inline renderer 9, model delivery 8, shared delivery 3, model storage 7, platform 16, model publisher 7, infrastructure publisher 13; all passed. Exact-byte heredoc execution passed. Configured model ZIP 3 and infrastructure ZIP 4 mocked cases passed, including a saved-Plan/fresh-Apply worker archive check.
- The current RMS source matches the committed baseline for all three changed production files, and its latest failed job matches request ID `53f60784ecba5ce984bf2dc418921802`.
