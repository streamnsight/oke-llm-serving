<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Active branch integration into main

Merge the user's active `fix/vllm-python-frontend` branch into main while retaining the general memory estimator already on main. Preserve the active worktree and integrate through an isolated branch. This integration changes repository source and local packages only; it does not update RMS uploads, execute pipelines or mutate GPUs.

## Phases

1. [x] Inspect branch divergence and worktree status; prepare an isolated merge. Git merged the overlapping discovery recipe/report/schema changes automatically, without conflicts.
2. [x] Validate combined source: all Terraform test roots with strict fake OCI CLI, full JavaScript suite and diff checks. Check model publication/deployment, inline delivery, LMCache and discovery together.
3. [x] Commit the tested merge, build the three actual archives from committed source, and validate their relocated roots with Terraform 1.5.7.
4. [x] Integrate into main after validation and rebuild local packages from merged main. Record commit/package provenance. Preserve the user's active branch and uncommitted work.

## Validation

Combined source validation passed: 331 Terraform test runs across 23 roots, and 168 JavaScript tests passed with 4 skipped. Parallel provider initialization caused transient plugin startup/exec-format failures; rerunning affected roots serially passed. A publisher assertion also caught nested maintenance tests in source-rendered bundles; both publishers now exclude nested test directories. Diff checks and automatic merge checks passed. No runtime or GPU compatibility claim is inferred from metadata/configuration tests.

The original `plan/general-model-memory` commits are patch-equivalent to the estimator commits already on main. The integration also records that original branch in ancestry while retaining the later estimator fixes on main.


Final archive checks passed under Terraform 1.5.7 for the discovery entry ZIP, both embedded downstream roots, and both standalone downstream ZIPs. The validated source is merge `f6c7b42`; its tree is identical to the tested frontend integration `1ee4410`. Main was advanced after validation. Both `fix/vllm-python-frontend` and `plan/general-model-memory` are recorded as ancestors. The latter merge preserves the newer estimator diagnostics and validation record, with no source-tree changes. Local packages are rebuilt from the final main commit; no push, hosted upload, RMS Apply or GPU mutation was performed.
