<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Multi-host startup DNS repair

The HTTP Service and LeaderWorkerSet currently share the Helm release name. Live controller events report that the existing Service has no LWS controller owner, preventing creation of the required headless Service. The leader hostname never resolves; vLLM retries its distributed TCP store for roughly twenty minutes. The supplied logs reach distributed initialization with TP=4, PP=2 and eight ranks; they do not demonstrate a GPU memory failure.

Use `<release>-http` for the multi-host HTTP Service, leaving `<release>` to the LWS controller. Preserve the single-host Service name. Update validation and benchmark clients according to the effective HOSTS_PER_REPLICA, including manual overrides. Monitoring selects only the chart HTTP Service labels; the controller's headless Service must not become an HTTP target. Helm upgrade removes the obsolete chart Service, allowing LWS to create its own. Do not patch serving images or dependencies for this networking failure.

1. [x] Add a failing chart regression and implement distinct names plus matching runtime clients; test single-host, multi-host and router selection.
2. [x] Validate real startup DNS with the installed LWS controller using disposable CPU-only fixtures. Run focused runtime/Terraform/archive checks. No GPU allocation, resize or recycling.
3. [ ] Commit and record validation. Update the current model stack source with the focused fix, preserving settings, and identify the supported redeploy path. Merge only after relevant validation; rebuild from committed main.

Validation so far: both new regressions failed against the original code. The updated model runtime/chart suite passed 38 tests (one optional upstream-router test skipped), and the additional benchmark endpoint matrix passed separately. Model delivery Terraform tests passed using the strict fake CLI. Live CPU-only upgrade reproduced the colliding ClusterIP and NXDOMAIN, then confirmed controller-owned headless discovery with publishNotReadyAddresses=true. No model image or GPU workload changes were applied.

The CPU fixture completed end to end: both Pods became Ready, LWS reported Available, and the distinct HTTP Service returned `ok` from `/health`. Its headless Service was controller-owned and published not-ready addresses; the HTTP Service remained a separate ready-leader endpoint. Both Pods were pinned to an existing CPU node and requested no GPU resources. The disposable Helm release and namespace were removed. The fixture used the exact production workload template with a small CPU DNS/HTTP process in place of vLLM. This validates the networking fix, not model loading or inference. Terraform model-delivery suite: 45 passed.
