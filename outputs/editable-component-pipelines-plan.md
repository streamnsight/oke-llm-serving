<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Editable component pipelines

Scope: the infrastructure platform bootstrap; the legacy combined model template is deferred. Keep the existing GPU debug switch enabled throughout live validation. LWS is the only shared component currently deployed. No GPU allocation, node changes, or workstation network changes are required.

1. [x] Inspect OCI Shell variable and artifact contracts. Use native command-spec environment variables populated from editable pipeline parameters; keep script contents out of substitution.
2. [x] Publish readable, checksum-addressed module scripts to private Object Storage. Replace encoded configuration with named variables and validate their types before use. Preserve original-spec readiness by isolating evidence for overrides.
3. [x] Separate LWS deploy/update and read-only platform validation into independently invoked pipelines. Preserve existing pipeline identity, explicit Kubernetes authorization and controller ownership checks.
4. [ ] Test environment overrides, script integrity, both pipeline modes, upgrade ownership, evidence isolation and packaging. Update the existing debug RMS stack using a reviewed saved Plan; run default deployment/validation without upgrading the live controller.
5. [ ] Document editable settings, component lifecycle, actual live results and limits. Commit, integrate after validation, rebuild the discovery package and remove temporary validation assets.

Design: parameters hold scalar strings only (booleans, counts, versions, names and locations); the runner builds its small typed readiness input with jq. The OCI API still requires base64 transport for an INLINE command-spec artifact, but the decoded command specification has no base64 code/configuration payloads. A separate LWS pipeline owns installs/explicit upgrades. The validation pipeline checks existing state without Helm/Kubernetes changes. Default LWS runs reuse matching healthy releases. Explicit upgrades must target the configured existing release and respect CRD field ownership. Serialize runs on a platform.

Sources: [command specifications](https://docs.oracle.com/en-us/iaas/Content/devops/using/command_spec.htm), [per-run pipeline parameters](https://docs.oracle.com/en-us/iaas/Content/devops/using/parameters.htm).

Local verification: 45 script/schema checks passed (two optional chart checks skipped), including 17 bootstrap cases. Publisher tests passed nine runs and the actual generated debug ZIP passed five. The infrastructure suite now passes eleven runs. A new regression reproduced an unintended namespace deferral/bucket replacement caused by module-wide depends_on when CoreDNS status changed from UPDATING to ACTIVE. That Plan was not applied. The module-wide dependency was removed, project creation retains a target-readiness precondition, and the regression now passes. The entry package and both embedded roots passed Terraform init/validate.

OCI integration detail: the artifact API rejects SUBSTITUTE_PLACEHOLDERS for COMMAND_SPEC. Keep argument_substitution_mode=NONE; Shell resolves references through native env.variables. The first Apply exposed this service constraint after creating script objects and the validation pipeline record; no pipeline was executed from that incomplete update and no cluster/GPU resources changed. Retry uses the native command-spec mode.
