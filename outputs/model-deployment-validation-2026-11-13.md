<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Discovery cleanup and model-stack creation validation

Validated November 13, 2026, Pacific time (November 14 UTC). Scope: simplify discovery and verify infrastructure-bound model packaging plus RMS pipeline creation. GPU runtime execution remains outside this validation.

## Discovery

The public root returns one `discovery` JSON and small count/navigation outputs. It retains every confirmed option's region, AD, exact shape, observed supply, whole-host entitlement, allocation, TP/PP, packed replicas, memory estimates and PAR/RMS links. Unknown memory remains null. Detailed diagnostic evidence is opt-in. The separate HTML page is an optional view of these choices; RMS does not render HTML.

Recipe metadata is shared across consumers. Equivalent hardware queries and exact previously resolved image references are reused. Unselected nightly/cache alternatives and hardware renderings without one whole host of confirmed supply/entitlement are skipped. The scanner reuses its subscription response, batches physical capacity reports by AD, checks only applicable quotas and skips limit lists when no relevant quota names exist. Later native allocation admission checks only the selected AD/shape and relevant regional/global quotas, requiring evidence for every shape quota.

Local verification passed: 14 CLI/report JavaScript tests, 46 planner tests, 10 root tests, 9 report tests, 10 native inventory tests and 24 allocation tests. These verify request counts and exclusion/sizing behavior, not a measured production speedup. The extracted entry ZIP and both embedded roots validate with Terraform 1.5.7.

## Live RMS flow

1. Updated the existing Frankfurt debug infrastructure stack while preserving `skip_gpu_allocation=true`. Inspected its saved Plan before Apply; no allocation/add-on execution resources were present. Apply succeeded, retaining the existing project, cluster environment and repositories.
2. Infrastructure published a model ZIP into the original Chicago discovery bundle bucket. Download through its PAR succeeded; SHA-256 matched the publisher output. The configured root ZIP validated with Terraform 1.5.7. Plan and Apply were separate RMS jobs, exercising archive creation on the Apply worker.
3. Created RMS stack `oke-llm-model-metadata-validation` from that actual ZIP, with only tenancy/compartment/region variables. Its saved Plan contained 53 managed resources, four pipelines and no automatic deployment, node pool, Compute Cluster, shared project or bucket resources. Apply succeeded: 53 added, zero changed, zero destroyed.
4. Final model state records all four pipelines ACTIVE and six stages: one `OKE_HELM_CHART_DEPLOYMENT` and five `SHELL` stages. Model state owns no GPU allocation or shared infrastructure.

| Pipeline | Role | Runtime execution in this validation |
|---|---|---|
| Deploy | Prepare/validate prerequisites, package chart, native Helm, validate release | Not run |
| Validate | Independent model/API checks | Not run |
| Benchmark | CPU client using official vLLM benchmark tooling | Not run |
| Undeploy | Ownership-checked release removal and drain | Not run |

The model stack OCID is `ocid1.ormstack.oc1.eu-frankfurt-1.amaaaaaafigrwqya46zwidmbrj3d7pjq74zhhuipvujzx3aw7bc6awbmneqq`. Its model namespace is `llm-platform-model-m-qwen-qwen3-8--cd680c`. Trusted namespace onboarding is provided but was not executed in this pass. Raw plans, state, logs and the configured ZIP remain private under `work/model-layer-validation/`; expiring PAR credentials are not committed.

The model specification uses Qwen/Qwen3.8-27B at revision `37561816e66b5b9153b1b64c10968c18c1e6f4a0`, with a roughly 55.56 GB checkpoint download. Its hybrid/multimodal memory estimator remains explicitly unsupported. The selected recipe configuration is an untested suggestion, and its older capacity observation was not refreshed for this metadata test. The debug binding has no GPU pool and cannot establish serving readiness.

## Remaining runtime work

After intentionally allocating retained GPUs, generate a fresh bound model bundle, grant its exact pipeline identities through trusted onboarding, then execute deployment validation and benchmarks. CUDA/kernel compatibility, placement, NCCL/RDMA, KV routing/cache behavior, task-specific APIs and teardown with live workloads remain unvalidated. Advanced cache companions and durable Responses/conversation storage require additional adapters described in [model-layer components](../docs/model-layer-components.md).

Original local discovery state, backup and tfvars hashes remained unchanged. User-owned AGENTS.md staging and the separate discovery review were preserved.
