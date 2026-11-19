<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->

# Discovery serving layouts and larger native P/D validation

## Scope and success criteria

Explain TP, PP, replicas, combined serving, separate prefill/decode, prefix caching and routing in discovery. Offer combined/P/D tabs with region/AD choices for each eligible configuration. A 1P/1D layout has two full-weight instance groups, but its whole-host allocation need not double an already replicated combined deployment. MoE is not a P/D exclusion; cache architecture, image/connector, recipe and topology compatibility determine eligibility.

Reuse each existing infrastructure/model archive. OCI's documented `zipUrlVariables` quick-create parameter carries small editable scalar presets for the selected tab; `zipUrl` and its bounded PAR remain unchanged. Downloaded ZIPs retain their ordinary defaults, so show the selected layout's overrides explicitly for manual uploads. Do not add tfvars, duplicate archives by serving mode, reuse combined counts as P/D quantities, or present unknown capacity/headroom as an available choice.

The first P/D planning adapter uses one prefill instance and the requested minimum decode replicas, matching TP and PP=1 with one host per instance. Fill spare complete GPU slots with decode instances, keeping role counts explicit. Recheck both role pools against physical capacity and entitlement in the same selected AD. No automatic GPU allocation or resizing is authorized for validation.

## Phase 1 — inspect and define

- [x] Inspect report, publishers, current capacity planner and native P/D contracts.
- [x] Verify OCI supports reusable quick-create ZIPs with editable scalar presets.
- [x] Split independent work across layout assessment, report UI and Qwen3-14B GPU validation.
- [x] Check out a feature branch in the main workspace; preserve independent agent branches.

## Phase 2 — implementation

- [x] Add pure layout assessment with model/recipe gates, per-role counts, whole-host packing and exact-AD capacity/headroom checks.
- [x] Integrate layout rows and bounded quick-create presets into report data without increasing publication/archive counts.
- [x] Add accessible tabs and model-specific explanations; keep unavailable configurations visible with reasons.
- [x] Preserve correct combined behavior and make manual ZIP defaults/presets explicit.

## Phase 3 — validation

- [x] Focused Terraform regressions for packing, quantity gates, unknown evidence, PP restrictions, compatible MoE and incompatible cache architectures.
- [x] Report/publisher regressions for shared ZIP identity, distinct editable presets, safe URL encoding and unchanged archive cardinality.
- [x] Browser-test actual tab, filter, sort and launch-link flows, including unavailable layouts.
- [x] Run Qwen3-14B BF16 with TP=2 per role on the existing four-A10 host, using only the previous owned test's explicit undeploy to release its GPUs.
- [x] Require safe model-only Plan, trusted onboarding/deploy/independent validation, native transfer observations, bounded manual benchmark, owned cleanup and refreshed no-op Plan.
- [x] Commit and integrate the validated discovery feature; rebuild actual archives from merged committed source and verify Terraform 1.5.7/RMS compatibility. Report publication scope honestly.

## Efficiency and edge cases

Reuse one capacity scan and existing model/recipe metadata. Layout derivation is linear in confirmed base options; it does not repeat recipe or GPU discovery. Client rendering remains linear in visible rows apart from sorting. Preserve scoped regional/global quota semantics from the planner's whole-host entitlement result. A tab is an alternative allocation, never additional capacity to add across tabs. Zero/unknown capacity, unknown quota units, incompatible recipe connectors, hybrid/multimodal layouts and unsupported PP remain unavailable. For a manual ZIP upload, link presets are not embedded defaults. Existing saved RMS variables and retained GPU pools do not change merely because report alternatives change.

## Validation record

The pure layout module passes 24 Terraform regressions; report data passes 22 and the root passes 21. All 29 executable report checks pass. The root regressions caught a null recommendation for empty reports; the guard and a focused report regression now cover that case. Headed Chromium checks passed desktop, 390px mobile without horizontal overflow, keyboard navigation, expanded role counts/manual presets and unsupported-layout reasons. Fixture browser evidence is under `/tmp/discovery-layout-tabs-preview`.

The scoped Montreal/A10/Qwen3-14B RMS discovery Plan from committed source passed and its JSON was reviewed: 14 publication-only creates, including exactly one infrastructure archive and one model archive. There are no GPU/instance/node-pool/volume or IAM mutations. Apply succeeded. The actual published schema-5 HTML passed browser desktop/mobile, selected-AD counts, role counts, filtering/sorting, keyboard and manual-preset checks. Both tabs use the same downloadable archives and byte-identical short launch copies. Both raw ZIP origins are 208 characters; launch URLs including presets are 358/652 characters, preserving the separate ZipOrigin limit.

The actual model archive passed five generated-root mock executions. The actual infrastructure archive passed four executions, including a two-host variable override and wrong-region rejection, with the existing fixed Phoenix test fixture scoped to the published Montreal region/selection/boot budget; checker/source logic stayed unchanged. Saved-Plan/fresh-worker archive creation also passed. A separate real RMS metadata-only Plan of the shared model ZIP with the P/D scalar presets succeeded: 50 model-owned creates, no hardware mutations, and materialized pipeline TP=4/PP=1/REPLICAS=1. It was not applied; the empty test stack metadata is cleaned after preserving the Plan. The authenticated Console quick-create form itself was not UI-tested: the isolated browser has no OCI session. URL parsing, documented parameter support and RMS variable/Plan behavior were checked separately.

An independent read-only integration review found no actionable issues in quantity math, reused archives, typed presets or runtime node derivation. The discovery feature was merged into local main at `3f1916d`; rebuilt entry/model packages passed the repository archive checks under Terraform 1.5.7. The published validation report uses committed feature source with the same functional discovery files. Existing uploaded discovery stacks/shared release bundles and remote Git branches are not changed by the local merge/rebuild. The independent larger-model GPU run is recorded below and in the native P/D validation plan.

The published recipe's conservative sizing selects TP=4, so that report compares one combined four-GPU host with a P/D pair needing two hosts/eight GPUs. The separate GPU test deliberately assesses TP=2 per role with the previously validated official vLLM 0.32.0 image. A successful smaller runtime does not automatically retrain discovery's recipe memory budget or certify another image. Private discovery evidence is under `/tmp/discovery-serving-layouts-live-20261119`; logs/state/PARs are excluded from source/packages.

Private live model evidence belongs under `/tmp/native-pd-qwen14b-20261119`, outside source/packages. The prior small-model deployment belonged exclusively to the earlier validation stack. Its owned undeploy succeeded. The 14B model-only Plan passed with no hardware changes, but its first Apply reached the tenancy's dynamic-group object quota before onboarding. After an actual reviewed local Destroy Plan and checks for absent workloads/released ownership/no active executions, that retired test stack's 50 model-owned resources were destroyed successfully to release its exact IAM group. Its owned repository cleanup hook deleted all 14 software artifact versions successfully. No user model, unrelated IAM group, retained GPU host or shared platform was removed. The reviewed partial-state 14B recovery Plan had five creates and 45 no-ops, with no hardware changes; its resumed Apply created the new model IAM normally and completed trusted onboarding.

Primary reference: [OCI quick-create links and zipUrlVariables](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/create-quick-create-links-stacks.htm).

The larger Qwen3-14B run completed successfully on the existing four-A10 host: TP=2 per role, one prefill and one decode, all owned onboarding/workload/independent-validation executions and Apply successful. The manual benchmark completed 128/128 requests across 1K/2K unique/shared-prefix cells; all observed native transfer, zero decode-side prompt recomputation and no transfer failures. Exact benchmark resources were cleaned and the Lease released; the refreshed RMS Plan reports 50 resources and outputs unchanged. The generic startup-deadline correction and full evidence are recorded in the model startup and native P/D plans. The owned validation discovery report was refreshed from committed fixed source `79a8d09`, and its downloaded shared model ZIP contains the correction. Unrelated uploaded stacks and shared release bundles remain unchanged.
