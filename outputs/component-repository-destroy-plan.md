<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Component repository destroy cleanup

Add destroy-time hooks directly to the platform-owned scripts and execution-results Generic Artifact Registry repositories, following oke-langfuse/app__common.tf. This avoids a separate cleanup resource that would require Apply before an already-failed Destroy. Terraform's existing repository references keep consumers ahead of repository deletion. Remove all stored versions, including versions no longer tracked by Terraform and pipeline-generated results; leave Kubernetes uninstall and retained GPU resources unchanged.

1. [x] Implement a module-owned Bash/OCI CLI cleanup helper with exact repository/compartment scope, region from the repository OCID, local profile and RMS delegated/principal auth, pagination, bounded deletion polling and explicit failure on errors. Attach hooks to both owned repositories without new inputs or IAM policy changes.
2. [x] Test populated/empty/deleting repositories, stale versions, foreign-repository responses, errors, auth and region behavior using a fake OCI executable; verify Terraform destroy lifecycle without cloud access and run affected module/template/package tests.
3. [ ] Validate generated infrastructure and packaged roots with Terraform 1.5.7, commit/integrate the tested fix into local main and rebuild discovery plus infrastructure ZIPs. Patch only the cleanup hooks/helper in the confirmed Frankfurt stack source, preserve its variables, and verify the downloaded source after upload. Preserve user edits/state. Do not run a live destroy, pipeline or GPU operation.

References: https://github.com/streamnsight/oke-langfuse/blob/main/app__common.tf ; https://docs.oracle.com/en-us/iaas/Content/artifacts/delete-repo.htm . The pinned OCI provider v9.13.0 generic upload resource's Delete function returns nil without removing stored content. OCI CLI supports full and short region identifiers from OCIDs; no region catalog or tenancy-wide artifact scan is needed.

Validation so far:

- Cleanup script tests: 10 passed. Platform module: 10 passed. Infrastructure template: 11 passed. Infrastructure publisher: 12 passed. Rendered infrastructure ZIP: 4 passed, including archive creation on a fresh Apply worker. Provider mocks still execute destroy provisioners; a strict CLI fixture and test wrapper prevent real OCI calls.
- The source-only patch for the confirmed Frankfurt stack passes Terraform 1.5.7 initialization/validation. ZIP comparison confirms only the platform module's repository definitions and its new cleanup helper differ from the downloaded source.
- No repository contents, Kubernetes components or GPU resources have been deleted. No live Terraform job has been started.
