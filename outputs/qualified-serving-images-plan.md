<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Qualified container references for CRI-O

Success means every generated serving/router/benchmark/staging image identifies its registry, image digests are preserved, private registry overrides remain intact, and the current model proceeds past ImageInspectError.

## Phase 1 — diagnose

- [x] Confirm the Pod now schedules after the approved filesystem repair.
- [x] Capture the CRI-O failure: enforcing short-name mode rejects `vllm/vllm-openai@sha256:...` as ambiguous even though it is digest-pinned.
- [x] Update only the live Deployment's registry prefix to `docker.io/`, preserving the repository and digest.

## Phase 2 — correct generated definitions

- [x] Qualify discovery's stable/nightly/platform image references without changing metadata API URLs or selected releases/digests.
- [x] Normalize serving overrides and frozen older specifications at the deployment boundary; preserve explicit registries/ports/localhost.
- [x] Qualify bundled router and CPU benchmark images, and normalize the optional staging image.
- [x] Reject ambiguous manual pipeline image overrides actionably before Helm.
- [x] Add focused resolver/deployment/runtime regressions and repository guidance.

## Phase 3 — deliver and verify

- [x] Commit, rebuild the discovery entry with both templates and validate actual generated archives with Terraform 1.5.7.
- [x] Preserve RMS values while updating sources, except the later user-requested model main override. The reviewed Plan had zero GPU infrastructure mutations; deploy and automatic validation succeeded. Benchmark remains manual.
- [x] Check actual Pod image pull/startup/health. A separate bounded chat request returned OK; the configured automatic inference probe remains disabled.
- [x] Check a refreshed RMS Plan: zero managed resource changes.

Live result: the fully qualified digest reference passed CRI-O inspection, the image pulled and vLLM started. The subsequent startup failure is the recipe-enabled Rust frontend rejecting the model chat template; image registry selection is no longer the blocker. Model and container digests remain unchanged.
