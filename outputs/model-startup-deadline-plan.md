<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->

# Model Deployment startup deadline

## Phase 1 — reproduce

- [x] Preserve the actual Qwen3-14B failure: Kubernetes marked both role Deployments ProgressDeadlineExceeded after its default 600 seconds, while healthy pods were still downloading/loading weights with zero restarts.
- [x] Confirm startup probes and the pipeline readiness budget allow 1800 seconds. The failure is the Deployment progress deadline, not evidence of memory or native KV-transfer incompatibility.
- [x] Reproduce the missing deadline with a rendered-chart regression covering ordinary and P/D Deployments.

## Phase 2 — implementation

- [x] Pass the existing bounded timeout into chart values and use it for Deployment progress and startup probes. Preserve the default probe specification exactly; no image, model, memory, GPU or filesystem changes.
- [x] Verify the actual old/new rendered PodTemplates are identical for the live default configuration, so the in-place Deployment-spec update does not restart weight downloads.
- [x] Run focused chart/runtime and Terraform checks. The new rendered regression fails without the deadline, then passes for default/300/901/1800-second budgets in both layouts. All 48 ordinary runtime/chart checks pass with one optional upstream-chart test skipped; all 55 preexisting delivery/execution Terraform checks pass.
- [x] Commit the generic fix and rebuild the owned model stack from committed source.

## Phase 3 — live validation

- [x] Wait for the existing loading pods to become Ready rather than patching status or restarting them; ProgressDeadlineExceeded can remain until real progress occurs.
- [x] Inspect the updated RMS Plan for GPU/instance/pool/volume mutations and recover through the owned onboarding/deploy/independent-validation workflow with ownership checks.
- [x] Finish native-transfer observation, the bounded benchmark and a refreshed no-op Plan. Record cold download/loading separately from serving performance.

Private failure logs, actual Deployment conditions, state and test output remain under `/tmp/native-pd-qwen14b-20261119`. Both 14B pods established TP=2 groups successfully. Each downloaded 27.51 GiB in approximately 468–471 seconds; subsequent cold shard loading took roughly one minute per shard with vLLM streaming and no prefetch under the current 16 GiB pod memory budget. These are cold-start observations, not request latency or throughput.

The fixed-source recovery Helm update is observed live: both serving Deployments have `progressDeadlineSeconds=1800` at generation 2. Both engine Pod UIDs and the router Pod UID are exactly unchanged, all Ready with zero restarts. The source correction therefore changed only the controller deadline for this default-budget deployment; it did not trigger weight downloads, image changes or GPU/node recycling. The reviewed recovery Plan contained 18 owned metadata/software/execution changes and no GPU, IAM or shared-platform mutations. Trusted onboarding, workload deployment, separate independent validation and RMS Apply all succeeded. The actual refreshed RMS Plan has all 50 resources and outputs unchanged. The manual benchmark stage succeeded with 128/128 requests, native transfer in all four cells, zero decode-side prompt recomputation and no transfer errors. Its exact Job/ConfigMap were removed and the model Lease released. Full cold-start and serving measurements are recorded separately in the native P/D validation plan and private `final-validation.json`.
