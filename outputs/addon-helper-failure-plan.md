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
- [ ] Pass focused executable/Terraform tests and validate RMS-compatible stack packages.
- [ ] Update the affected RMS source only, preserving variables and submitting no Apply or GPU operations.
- [ ] Commit, merge into local main and rebuild packages; record remaining live-validation limits.
