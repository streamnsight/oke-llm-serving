<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Discovery HTML and independent model project validation

Date: 2026-11-14. Scope: discovery publication, browser presentation and model DevOps metadata creation. GPU allocation, node lifecycle operations and model/onboarding/staging pipeline execution are excluded. Private raw evidence is retained under `work/html-report-validation/`; PAR credentials and Terraform state are not committed.

## Discovery and browser checks

A packaged discovery stack ran in RMS with Qwen/Qwen3.8-27B, pinned revision `37561816e66b5b9153b1b64c10968c18c1e6f4a0`, 4,096 context tokens and four concurrent sequences. The diagnostic scan was restricted to Frankfurt and BM.GPU.A10.4; it was not an all-region scan. Saved Plan inspection admitted only publication resources before Apply.

The initial Apply succeeded and exposed exactly one output, `comparison_report_url`. Its Object Storage PAR served the self-contained HTML successfully. The report showed three confirmed AD options, 32 GPUs reported across the exact shape's three ADs, TP4/one replica per four-GPU host, recipe/image provenance and both infrastructure/model PAR and regional RMS links per option. Publication expiry was shared across all links. These are observations, not reserved hosts.

The model's composite/hybrid memory estimate remained explicitly unknown; the page displayed the Hub-published 55.56 GB checkpoint download size and a separately labeled 71.83 GB heuristic recipe sizing budget. It did not present that budget as measured runtime use or a validated per-rank fit.

The actual hosted page rendered and expanded correctly with no browser warnings/errors. Fixture-based desktop/mobile checks also exercised collapsed options, commands, both link groups, filtering/sorting, no-option/unknown-memory cases and a 390-pixel viewport without horizontal document overflow. No report interaction performs discovery requests. Styles came from the supplied Redwood package and were embedded with the script/data; no external runtime was needed.

## Model project creation

The model ZIP downloaded from the actual discovery PAR passed native Terraform 1.5.7 validation. Its RMS variables contained only `cluster_id` plus tenancy/compartment/region context normally populated by RMS. Native lookups resolved the existing cluster and network; no managed GPU pool existed, so pool readiness was deferred.

The first Plan succeeded with 60 managed metadata resources, one independent project, four pipelines and two Generic Artifact repositories. A guard rejected all managed Compute/node-pool/add-on resources and automatic DevOps executions. Two initial Apply attempts caught the same service naming constraint, first for Notifications and then for the DevOps project: the generated model name contained consecutive hyphens. Both now use one normalized service name, with a focused passing regression covering both. Corrected bundles were republished before retrying the same model stack. Repeated diagnostic discovery plans retained the Frankfurt/single-shape filter; they did not expand into an all-region scan.

The corrected discovery Apply and model Plan/Apply succeeded using implementation commit `45e6cd0`. Service API verification confirmed a separate model project (different from the platform project), an ACTIVE private OKE environment, four ACTIVE pipelines and six ACTIVE stages: one native Helm stage and five Shell stages. There was still no matching GPU pool; the model target remained deferred. Terraform state contained no managed Compute/node-pool/add-on resources or automatic DevOps executions. Default direct-Hub mode created no weight bucket/staging pipeline. Source/results repositories belonged to this independent model stack.

The actual final published model ZIP also passed both extracted-root mocked tests: independent metadata creation before GPUs exist and autoscaling's standard metrics endpoint. The same ZIP passed native Terraform 1.5.7 init/validate. The hosted final report retained all three choices and both link groups, expiring together at `2026-11-15T17:52:29Z`. These temporary validation bundles intentionally default their infrastructure stack to skip GPU allocation; normal discovery defaults do not skip it.

## Local verification

- Full JavaScript/shell validation suite: 90 passed, zero failed, three skipped. Skips were the platform-specific archive test and environment-gated upstream render checks; the pinned model-router render was also run separately and passed.
- Terraform mocks passed for discovery root (11), report (13), model profile (13), planner (46), target lookup (7), model project (3 including the naming regression), model delivery (4), staging (6), platform (10), infrastructure publisher (12) and model publisher (7).
- Executable onboarding cases (7) and model lifecycle checks, including the pinned router render, passed. These simulate service/Kubernetes boundaries; they are not live inference evidence.
- Extracted generated model roots passed independent-project and autoscaling-default mock checks. The entry ZIP, its two embedded template roots and an actual published model ZIP passed native Terraform 1.5.7 init/validate.
- Browser UI checks covered the live report and responsive fixture cases. Syntax, formatting and diff checks passed.

## Remaining runtime boundaries

No model deploy, validate, benchmark, undeploy, namespace-onboarding or weight-staging pipeline was executed in this validation. The cross-project onboarding logic has local executable coverage; existing deployed platform onboarding software must be updated before using the new project identity flow. No GPU nodes, pools, Compute Clusters or reservations were allocated, resized, cycled or deleted.

Real GPU scheduling, driver/CUDA/NCCL/RDMA compatibility, weight materialization, inference modalities, cache behavior, durable conversation state and performance remain unvalidated on hardware. Free GPU headroom across other model namespaces is intentionally unknown to model preflight; Kubernetes resource requests and bounded rollout establish placement. Generic Artifact IAM remains compartment-scoped rather than a project isolation boundary.
