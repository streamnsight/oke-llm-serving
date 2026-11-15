<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Shared controller capabilities and per-model policy

LWS coordinates leader/worker Pod groups and DisaggregatedSet child groups, including one-Pod roles on the same GPU host. Single-Pod tensor parallelism is performed by vLLM. DisaggregatedSet provides role orchestration for an explicitly configured prefill/decode topology, not automatic KV-cache optimization. Leave topology-derived defaults, clarify both controls, and ensure enabling DisaggregatedSet also selects LWS. Install/reuse shared KEDA by default independently of any model's autoscaling policy; model autoscaling stays opt-in and creates its own ScaledObject only when selected.

1. [x] Rename the infrastructure choice to keda_enabled, default true, separate its capability output from model autoscaling, and update generated defaults, UI descriptions and dependent-controller selection. No compatibility aliases or discovery inputs.
2. [x] Verify KEDA installed with model autoscaling off, independent KEDA/Prometheus installation, explicit all-off/reuse/retire behavior, DisaggregatedSet implying LWS, generated editable defaults, and model-only ScaledObject policy. Run affected mocked tests and package checks without GPU allocation or controller deployment.
3. [ ] Validate packaged roots with Terraform 1.5.7, integrate into local main, rebuild discovery/infrastructure/model packages and update the existing component stack source/form without running it. Document the resulting defaults. Preserve user edits; do not run live Apply/Destroy or pipelines.

Sources: https://docs.vllm.ai/en/stable/deployment/frameworks/lws/ ; https://lws.sigs.k8s.io/stable/docs/concepts/disaggregatedset/ ; https://keda.sh/docs/2.21/setupscaler/ .

User clarification: disaggregation partitions prefill/decode roles across GPU allocations, not necessarily nodes. Corrected the descriptions accordingly. The current model workload chart has no DisaggregatedSet rendering adapter; controller installation must not be presented as a completed P/D deployment.

Validation so far:

- Platform, infrastructure template, model delivery, infrastructure publisher and model publisher Terraform suites passed: 12 + 11 + 7 + 13 + 7 cases. Generated infrastructure passed 4 cases and both generated model variants passed 3 cases each.
- Renderer/form/model Helm tests passed (38 cases; 2 optional upstream-chart tests skipped), with the model suite rerun after adding the no-ScaledObject default assertion (20 passed; 1 optional full-router test skipped). No controllers, model Pods, GPUs or live pipelines were deployed.
- The generated-model fixture assumed every option had a platform_plan; removed that unrelated prerequisite so it verifies model-owned policy on both recipe and candidate archives.
- A source-only update for the existing component stack preserves its retained GPU/debug settings and cleanup hooks, changes the infrastructure KEDA capability name/default, and passes native Terraform 1.5.7 validation. Upload/verification remains in phase 3.
