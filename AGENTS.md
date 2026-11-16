<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
make sure to include the mention

```
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.

```

as a header for every file in this repo (as long as it doesn't discrupt its function, that is, excluding JSON or other files that cannot take comments)

# Repository working patterns

## Stack and module organization

- The repository root is the discovery stack and the single released entry ZIP. Keep downstream roots under `templates/infrastructure` and `templates/llm-deployment`.
- Group modules by stage and responsibility: `modules/discovery`, `modules/infrastructure`, `modules/cluster-add-ons`, `modules/llm-deployment`, and `modules/shared`. Put reusable delivery mechanisms in shared modules; do not combine infrastructure and model ownership again.
- Keep runtime scripts, command-spec templates, Helm charts and data catalogs inside their owning module. Root `scripts/` and `tests/` are development, testing and packaging tools.
- Resolve runtime assets with `path.module`. Update the publishers' explicit module dependencies whenever adding a runtime module. Generated ZIPs must have `main.tf`, `schema.yaml` and their relocated `modules/` at the archive root.
- Keep a written phased plan and validation record for substantial changes. Build from committed source, validate the actual generated archives, and rebuild packages after merging. A local rebuild does not update existing Object Storage bundles or RMS stack uploads.
- Preserve unrelated staged/unstaged user edits. Use an isolated feature branch/worktree, commit the feature, and integrate only after the relevant checks pass.

## Discovery and deployment ownership

- Discovery accepts model/sizing inputs, inspects structured model/recipe metadata and scans subscribed regions for physical GPU capacity and entitlement. Prefer native Terraform providers; use module-local OCI CLI helpers only for actual provider gaps.
- Show deployable choices only when physical capacity and applicable limit/quota headroom are confirmed for the requested quantity. Show capacity-backed limit-increase alternatives separately. Never present zero-capacity or unknown-capacity rows as deployment choices.
- Keep discovery simple: one user-facing HTML report link, with model memory assumptions, ranked choices and generated infrastructure/model ZIP launch links. Counts must identify their region/AD scope and distinguish physical capacity, current limits and remaining headroom.
- Monitoring, component selection, model distribution, deployment overrides and GPU-allocation debugging belong to downstream deployment stacks. Keep recommended defaults editable in Terraform declarations and RMS schema; do not hide them in tfvars that shadow Console edits.
- Infrastructure owns retained GPU pools, optional Compute Cluster placement and shared controllers. It reuses existing CPU pools. Each model has its own deployment project and lifecycle, reusing the selected cluster/pool and compatible shared components.

## Readable pipeline artifacts and execution

- Keep scripts as readable `.sh`/`.jq` files in the repository and test those sources. Small scripts/configuration should be delivered through readable inline command specs rather than many Generic Artifact files.
- Inline commands must be ordinary Bash/YAML or quoted heredocs. Never embed base64 script/config blobs, add runtime base64 decoding, use eval to reconstruct code, or paste opaque encoded payloads into commands. For the locked OCI provider's `INLINE` source, pass raw text to Terraform's misleadingly named `base64encoded_content` field: the Go SDK serializes `[]byte` to base64 automatically. Do not add `base64encode()` there. CLI/Python SDK string fields have a different boundary; verify the exact client/type rather than copying their encoding into Terraform.
- Put non-secret settings in named pipeline parameters/environment variables so users can edit and rerun independently. OCI Managed Shell can reinterpret quotes and escapes in environment assignments. Use plain scalars or simple delimited identifiers, and parse/validate them in the owning script; deliver complex structured content as a file. Verify the actual runtime as well as the stored API argument. Keep credentials in service principal/Vault flows; never dump tokens, private config or all environment variables to logs/state.
- Measure the complete raw UTF-8 provider input against the 51,200-byte content limit, including YAML/helpers/configuration; report wire-encoded length separately. Mock providers do not exercise SDK serialization: check the pinned provider/SDK and verify a refreshed no-op Plan as well as Create success. Reuse existing immutable file inputs for large shared libraries instead of duplicating them inline or creating new uploads.
- Use native Helm stages for chart releases and Shell stages for prerequisites, raw CRDs, validation and explicit teardown. Charts belong in OCIR. Required file inputs and downloadable benchmark exports belong in Generic Artifact Registry. Routine deployment, readiness and failure summaries belong in stdout/stderr and DevOps Logging; do not create a report-upload dependency for a deployment. Object Storage is for discovery reports/ZIPs/PARs and explicitly selected retained model data.
- Fully qualify all Kubernetes image references, including serving, router, staging and benchmark images. CRI-O enforcing mode can reject a Docker Hub short name even with a digest. Preserve explicit registries and digest identity; qualify Docker Hub references before rendering and reject ambiguous manual pipeline overrides before Helm.
- Keep model compatibility fixes generic and use supported serving arguments/environment settings with upstream images. A recipe-selected image is not proof that its bundled libraries work together. Reproduce failures in that exact image before changing it; do not add hidden runtime package installs or model-specific image patches. Preserve the assessed Hugging Face commit as evidence when an expert explicitly chooses the moving `main` revision for direct Hub delivery.
- Chart version tags must match chart metadata exactly, including a leading `v`. Verify the upstream chart and reject mismatches before pushing a tag the native Helm stage cannot fetch.
- Use file-backed `source` uploads for Registry artifacts where possible so the OCI SDK can rewind and retry upload bodies. Do not use large inline Terraform `content` streams as a retry workaround.
- Infrastructure Apply must launch the component coordinator after required stages/artifacts/IAM exist and wait for terminal success, including component readiness checks. A failed child or failed validation must fail Apply. Keep independent components parallel and dependencies explicit.
- Model Apply must run trusted platform namespace onboarding, workload deployment and a separate validation execution in sequence, waiting for success; benchmarks remain manual. Discover the actual retained pool and trusted onboarding from the cluster, and check existing namespaces before acquiring model Leases. A failed Lease create followed by an empty read is not an existing Lease and must never enter compare-and-swap replacement.
- Trigger automatic execution from meaningful deployment revisions. Exclude volatile capacity reports, add-on inventory and retained/additional-node observations from revision hashes. Do not use timestamps or `trigger_new_devops_deployment=true` to rerun every unchanged Apply. Keep standalone component upgrade/validation/undeploy pipelines available.
- Deleting Terraform pipeline/deployment metadata does not uninstall Helm releases. Use explicit owned undeploy operations, preserve shared CRDs/PVCs as documented, and never infer component removal from metadata destruction.
- Removing Generic Artifact resource blocks does not necessarily delete the stored versions. Prune only exact obsolete software artifacts after verifying current definitions no longer reference them and no old execution remains active; keep results and model data separate.
- Do not overlap coordinator and manual updates of the same release. Preserve ownership/generation checks and compare-and-swap leases. Use explicit recovery with deployment evidence; never blindly remove an active or foreign lease to make a test pass.

## OKE, OCI CLI and validation

- Prefer OKE-managed hardware add-ons over competing standalone GPU/Network Operators. Enable missing required add-ons, reuse enabled installations/settings and retain shared add-ons when removing a stack. Read actual Operator configuration instead of assuming omitted summary fields mean enabled defaults.
- Detect OCI CLI command capabilities instead of assuming version ordering. Local preview CLI and RMS CLI can expose different layouts, including `ce addon ...` versus `ce cluster ...-addon(s)`.
- OCI DevOps ListStages summaries in the pinned provider can omit display name and pipeline ID even when the service returns them. Use the native stage-detail data source before verifying trusted execution boundaries; do not treat incomplete summary fields as authoritative.
- Base fixtures on real serialized API responses: add-on list responses can be arrays of `name` summaries and omit configurations. Use detail reads when required. Mock-only tests do not prove RMS behavior.
- Shell errors must identify the failed operation and exit status without exposing secrets. Reporting must preserve the primary failure and exit status instead of masking it with a secondary artifact-upload error. Preserve a diagnostic stream outside temporary-file redirections so silent CLI exits remain visible in RMS logs.
- Start with focused executable regressions, then Terraform tests and Terraform 1.5.7/RMS archive checks. Use `scripts/test-terraform.sh`: provider mocks do not prevent local-exec/destroy hooks from running, so strict fake CLIs must block unintended OCI calls.
- Validate service behavior in RMS when local and service runtimes differ. Separate metadata-only checks, component execution and GPU/runtime validation in reports; never claim a Plan or pipeline definition proves a running model.
- Custom OKE boot-volume size does not grow the worker filesystem automatically. Fetch the standard OKE init script through IMDSv2, run `oci-growfs` before OKE initialization, and verify actual kubelet ephemeral-storage capacity. Privileged maintenance Pods must enter host IPC as well as mount/PID/root namespaces before LVM commands; a private IPC namespace isolates device-mapper cookies from host udev. Dry-run success alone does not test that coordination. Existing workers need a separately reviewed in-place repair; changing pool metadata is not a filesystem repair and must not trigger GPU recycling as a workaround.
- Never allocate, resize, recycle or delete GPUs merely to test metadata/component changes. Inspect live plans before applying and ensure they contain no GPU resource mutations. GPU health monitoring does not authorize automatic node repair.
- Preserve state/tfvars/private logs and never package them. Keep development dependencies in temporary worktrees; do not leave node_modules, generated binaries or unused legacy assets in the working source.
