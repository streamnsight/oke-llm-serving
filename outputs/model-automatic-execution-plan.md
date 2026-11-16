<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Automatic model deployment and namespace prerequisite

Success means model Apply runs trusted onboarding, workload deployment and independent validation in order, waits for success and leaves benchmarking manual. No GPU infrastructure is changed by this stack.

## Phase 1 — diagnose

- [x] Inspect the failed execution and its exact command source.
- [x] Confirm the primary failure: the model namespace did not exist before Lease acquisition; Helm had not run.
- [x] Correct INLINE transport separately: pass raw provider content and let its Go SDK encode it once.

## Phase 2 — implement

- [x] Infer the trusted platform onboarding pipeline from the selected retained allocation and verify its fixed cluster/platform/project bindings.
- [x] Add native Terraform deployment resources for onboarding, workload and validation with terminal-success checks and explicit dependencies.
- [x] Derive reruns from effective runtime/code/binding revisions, excluding volatile discovery and pool observations.
- [x] Check an existing namespace before acquiring a Lease; never replace a nonexistent or unversioned Lease after a failed create.
- [x] Keep PVC safety based on the freshly inspected GPU pool, even when stable configuration records only the model minimum.

## Phase 3 — verify and deliver

- [ ] Pass focused runtime and Terraform lifecycle regressions, including failure propagation and unchanged revisions.
- [ ] Validate the configured generated model ZIP and RMS Terraform compatibility; rebuild discovery with both embedded templates.
- [ ] Preserve current RMS settings, review a Plan for no GPU infrastructure mutations, then Apply the authorized execution chain.
- [ ] Confirm actual onboarding/workload/validation outcome, and use a refreshed Plan to check idempotency.
- [ ] Commit the usable feature branch and record live limits accurately.

Routine readiness/failure summaries stay in DevOps Logging. Existing ownership, lease and namespace authorization boundaries remain enforced. An inference probe disabled by configuration does not prove token-generation performance.
