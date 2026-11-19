<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->

# Repository consolidation — 2026-11-19

## Phase 1 — audit and preserve

- [x] Inventory all local branch ancestry, patch equivalence, registered worktrees, tracked edits and nonignored untracked files.
- [x] Confirm the older memory, LMCache, benchmark, frontend, recipe-service and revision branches are already ancestors of main; no unique legacy feature commits are missing.
- [x] Identify the two apparent unmerged branches as patch-equivalent cherry-picks: `feat/pd-layout-assessment` and `feat/discovery-layout-tabs`.
- [x] Commit the current truthful validation notes before integration. Preserve the active deadline-fix worktree and its test process.
- [x] Back up all Git refs and completed-worktree ignored state/log/configuration files privately, excluding reinstallable provider binaries and node_modules.

## Phase 2 — integrate and clean

- [x] Merge the two patch-equivalent branch histories. Resolve the UI conflict by retaining the newer per-instance capacity wording; assert both ancestry merges leave the tracked tree unchanged.
- [x] Merge the generic startup-deadline correction into the consolidation branch. Its source matches the committed runtime-fix branch exactly, with no model/image/resource-budget overrides.
- [x] Remove only clean, completed worktrees after rechecking ancestry and preserving private files. Keep branch refs for history and keep active worktrees until their work finishes.
- [ ] Complete the in-progress Qwen3-14B runtime validation and integrate its truthful evidence record.

## Phase 3 — verify coherent main and packages

- [x] Verify every local branch's commits are included in the final integration head; retain any future/new edits rather than forcing removal.
- [ ] Merge the validated consolidation into main and rebuild release archives from committed main. Validate the actual archives and refresh the owned discovery publication so its model ZIP includes the startup-deadline correction.
- [ ] Record final branch/worktree status, private backup locations, test results and publication scope. Do not claim a remote push or update unrelated RMS stacks.

## Evidence and constraints

Private audit, full Git bundle, ignored-file archives and cleanup manifests live under `/tmp/oke-repository-consolidation-20261119`, outside source/packages. The first audit found 13 worktrees: the main workspace, one active deadline-fix worktree and 11 clean completed worktrees. The older branches had no unique commits or tracked/nonignored untracked changes. The two recent layout branches had one patch-equivalent commit each, already delivered to main through cherry-picks. No branch history is discarded by the consolidation.

Both branch-ancestry merges were checked for an empty tree diff against their first parent; the UI conflict preserved the newer capacity wording. All 11 completed worktrees were removed without force after fresh clean-status and ancestry checks. Private ignored files were archived before removal; only reinstallable node_modules/provider binaries were omitted. After the runtime agent confirmed its tests/builds were complete and no process depended on its checkout, the clean integrated deadline-fix worktree was also backed up and removed. Only the user's main workspace remains registered. Every local branch head is now an ancestor of the consolidation head, including the original runtime-fix commit; no patch-only equivalent remains outside the integration graph.

The final integration audit checked all 83 local/remote branch refs: none has commits outside the integration head. Branch names are retained for traceability; the source is consolidated in one graph and one registered workspace. The owned discovery publication was refreshed successfully from committed integration source `79a8d09`; its downloaded shared model ZIP contains the corrected startup deadline in both model Deployment templates, with the existing same-ZIP tab presets preserved. No unrelated RMS stack or GPU allocation was changed.

The startup-deadline fix has executable rendered-chart coverage, 48 passing runtime/chart checks (one optional upstream chart skipped), 55 prior delivery/execution Terraform checks and the focused native P/D budget checks. Live recovery is still required before marking its GPU workflow validated. The larger test and all cloud resources remain scoped as documented in the native P/D and discovery-layout validation plans; consolidation itself allocates no cloud resources.
