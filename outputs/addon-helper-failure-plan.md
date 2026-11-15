<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# OKE add-on helper failure

## Phase 1 — reproduce
- [x] Recover the failed RMS execution context and identify where exit 2 occurs.
- [x] Add an executable regression case matching that environment.

## Phase 2 — fix
- [x] Correct the failing invocation or authentication path with a focused change.
- [x] Report failed operations and their exit status without exposing credentials.

## Phase 3 — deliver
- [x] Pass focused executable/Terraform tests and validate RMS-compatible stack packages.
- [x] Update the affected RMS source only, preserving variables and submitting no Apply or GPU operations.
- [x] Commit, merge into local main and rebuild packages; record remaining live-validation limits.

## Validation record

- Reproduced the original empty exit 2 with the previous helper and real OCI CLI 3.79.0. Two regression cases failed before the fix: classic CLI commands and silent-error diagnostics.
- Passed 11 executable helper cases and 5 Terraform tests. Fixtures now use the actual array-of-name-summaries API response; Operator settings are fetched separately rather than inferred from missing summary fields.
- A separate, read-only RMS Terraform 1.5.x Plan succeeded against the same Montreal cluster. RMS reported OCI CLI 3.95.1, selected `ce cluster list-addons`, and read all six installed add-ons. The probe contained no managed resources and no installer invocation. Its temporary RMS stack was deleted afterwards.
- Validated the rebuilt discovery archive and both embedded downstream Terraform roots with Terraform 1.5.7.
- Patched only the helper and source-provenance manifest in the failed Montreal component stack. Downloaded the ZIP again and verified every file, unchanged variables and unchanged component job IDs.
- No component Apply/Destroy, DevOps pipeline, add-on installation or GPU operation was executed. Installation still requires a fresh component Plan and Apply; the previously saved Plan predates this patch.
