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

- [ ] Add pure layout assessment with model/recipe gates, per-role counts, whole-host packing and exact-AD capacity/headroom checks.
- [ ] Integrate layout rows and bounded quick-create presets into report data without increasing publication/archive counts.
- [ ] Add accessible tabs and model-specific explanations; keep unavailable configurations visible with reasons.
- [ ] Preserve correct combined behavior and make manual ZIP defaults/presets explicit.

## Phase 3 — validation

- [ ] Focused Terraform regressions for packing, quantity gates, unknown evidence, PP restrictions, compatible MoE and incompatible cache architectures.
- [ ] Report/publisher regressions for shared ZIP identity, distinct editable presets, safe URL encoding and unchanged archive cardinality.
- [ ] Browser-test actual tab, filter, sort and launch-link flows, including unavailable layouts.
- [ ] Run Qwen3-14B BF16 with TP=2 per role on the existing four-A10 host, using only the previous owned test's explicit undeploy to release its GPUs.
- [ ] Require safe model-only Plan, trusted onboarding/deploy/independent validation, native transfer observations, bounded manual benchmark, owned cleanup and refreshed no-op Plan.
- [ ] Commit and integrate only validated work; rebuild actual archives from merged committed source and verify Terraform 1.5.7/RMS compatibility. Report publication scope honestly.

## Efficiency and edge cases

Reuse one capacity scan and existing model/recipe metadata. Layout derivation is linear in confirmed base options; it does not repeat recipe or GPU discovery. Client rendering remains linear in visible rows apart from sorting. Preserve scoped regional/global quota semantics from the planner's whole-host entitlement result. A tab is an alternative allocation, never additional capacity to add across tabs. Zero/unknown capacity, unknown quota units, incompatible recipe connectors, hybrid/multimodal layouts and unsupported PP remain unavailable. For a manual ZIP upload, link presets are not embedded defaults. Existing saved RMS variables and retained GPU pools do not change merely because report alternatives change.

## Validation record

Pending implementation and execution. Private live model evidence belongs under `/tmp/native-pd-qwen14b-20261119`, outside source/packages. The prior small-model deployment belongs exclusively to the earlier validation stack and may be undeployed to make room; no user model or GPU host may be removed.

Primary reference: [OCI quick-create links and zipUrlVariables](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/create-quick-create-links-stacks.htm).
