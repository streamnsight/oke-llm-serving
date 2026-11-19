<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->

# Model revision defaults

The prior direct-Hub recovery used `main` because the selected image's Hugging Face revision serialization failed with a commit object. Discovery must retain its assessed immutable commit as evidence, but new direct-Hub deployments should default to the working `main` ref. Explicit commits remain supported, and retained PVC/staged snapshots continue to require immutable commits.

## Phase 1: Reproduce and define the boundary

- [x] Trace generated schema/default overrides and deployment fallback.
- [x] Confirm the prior image reproduction and live recovery in `outputs/vllm-frontend-startup-plan.md`.
- [x] Add a regression proving generated Terraform and RMS schema default to `main` without changing assessed model evidence.

## Phase 2: Implement consistent defaults

- [x] Align template, publisher, and direct-Hub module defaults.
- [x] Preserve immutable snapshot requirements and explicit commit overrides.
- [x] Document that refreshed source/defaults do not override saved variables in existing RMS stacks.

## Phase 3: Validate and deliver

- [x] Run focused publisher/delivery/execution tests and shell/runtime regressions.
- [x] Validate an actual generated model ZIP, including Terraform 1.5.7 compatibility.
- [ ] Commit the isolated revision change and report validation evidence to the integration agent.

No live stack changes, model redeployments, or GPU operations are part of this fix.

Validation: the new publisher assertion reproduced the stale SHA default before the fix. Publisher tests passed 11/11; model delivery/execution tests passed 49/49; runtime script/chart tests passed 42/42 with one optional upstream-router chart check skipped; the focused revision test also passed. An actual generated ZIP passed five generated-root tests with locked OCI 9.13.0 and validated with Terraform 1.5.7. These are metadata/runtime-script checks; no new live model deployment was necessary or performed.
