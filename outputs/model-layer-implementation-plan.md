<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Discovery presentation and model deployment workflow

Historical plan, completed 2026-11-13. The shared-project, infrastructure-bound model publisher and JSON output described here have been superseded by the [HTML report and independent model project plan](discovery-html-report-plan.md). Current usage is documented in [the model binding contract](../docs/model-binding.md).

Status: implemented and validated through live RMS pipeline creation; GPU runtime validation remains deferred. This feature builds on the CPU-validated component foundation. GPU allocation, pool resizing/cycling/deletion and model workload execution are not authorized for this validation. Preserve the user's staged AGENTS.md and untracked discovery review. See [the validation record](model-deployment-validation-2026-11-13.md).

## Outcome and boundaries

Users discover an open-weight model, compare every capacity-confirmed deployment choice, provision or reuse retained infrastructure, and create a separate model-only DevOps deployment. An expert can adjust generated defaults and pipeline parameters. Operators can validate, benchmark and undeploy a model without changing GPU pools, shared controllers, project or model data.

The current pass must create the model stack and its pipeline resources in RMS without GPUs. Actual CUDA/NCCL, GPU placement, inference, cache transfer, routing behavior and throughput remain pending hardware validation. Terraform Apply creates delivery resources; it does not automatically execute model deployment.

## Architecture and choices

- Organize modules under discovery, infrastructure, cluster-add-ons, llm-deployment and shared. Retain relative module addressing and root-level main.tf in every published ZIP. Module movement must preserve Terraform resource addresses.
- Expose one compact model/capacity/options report with complete per-option PAR and RMS links; keep detailed diagnostics behind an explicit flag. Remove obsolete large inline JSON handoffs. Share one recipe metadata snapshot; deduplicate full hardware render queries, reuse known exact image/tag SHAs, omit unrelated quota requests and do not fetch unselected alternatives. Diagnostics expose evidence without additional exploratory scans. Capacity counts are shape/AD observations, never a sum across alternative shapes or shared quotas.
- Separate available host/GPU counts, required GPUs per replica, allocated host/GPU counts and packed serving replicas. Memory fields retain source, units and unknown values.
- Model deployment reuses cluster, retained allocation selector, DevOps project, OKE environment and Generic Artifact repositories. It owns model release/pipelines and narrowly scoped delivery IAM, with no Compute/node-pool management.
- Use a small repository workload chart plus a pinned router-only Production Stack dependency; upstream chart alone has no native LWS template. Use native Helm for model charts and readable artifact-backed Shell stages for preparation, validation, vLLM benchmarking and guarded teardown. Preserve frozen recipe argv/environment as data.
- A vLLM operator is optional, not required on top of Deployment/LWS. Gateways/routes, model cache instances, ServiceMonitors and ScaledObjects have model lifecycle; shared gateway controllers remain infrastructure capabilities when needed. Durable Responses/conversation storage is an API/data layer, separate from KV cache reuse.
- LMCache local RAM/disk needs no database by default; distributed/external tiers require explicit compatible service/storage configuration. Never infer a backend solely from the presence of a connector flag.
- Publish an infrastructure-bound model ZIP using the selected model/recipe and actual infrastructure outputs. Embed editable HCL/schema defaults rather than a large RMS JSON variable. No secrets enter bundles or pipeline parameters.

## Phases and verification

1. [x] Reorganize module/template paths and document ownership. Verify relative references, Terraform roots and package closure; commit this mechanical change independently.
2. [x] Replace redundant discovery output with compact model summary and all confirmed option rows, including links and supply/allocation/replica/memory distinctions. Test unavailable/unknown exclusions, AD granularity, units and correct total-GPU ranking.
3. [x] Build model-only configuration/chart and artifact-backed deploy/validate/benchmark/undeploy pipelines. Test recipe argument preservation, single-node/replica/LWS renderings, namespace/ownership, retained data and no infrastructure resources/permissions.
4. [x] Bind and publish the model stack from infrastructure with matching editable defaults, existing-project/environment/repository references and small RMS input requirements. Validate extracted root ZIPs and configured defaults.
5. [x] Run Terraform/script/render/package checks and RMS Plan/Apply for pipeline creation only. Programmatically reject pool, Compute, reservation or shared-platform destruction; do not run model deployment/benchmark pipelines.
6. [x] Document exact supported adapters, missing infrastructure/model/API capabilities and validation limits; clean generated development assets, commit feature changes and preserve user edits. Main integration requires the relevant end-to-end validation, now completed for the scoped pipeline-creation workflow.

## Discovery simplicity pass

- [x] Share recipe metadata and identical rendered hardware/image lookups; disable unselected alternatives in the root.
- [x] Expose one discovery JSON with every confirmed option and an optional separate HTML view.
- [x] Query only relevant shape quotas and batch physical capacity requests by AD.
- [x] Reuse the subscription response after discovering the home region.
- [x] Narrow later native allocation admission to the selected AD and shape; remove its unused subscription lookup. Require evidence for every shape quota, including regional/global quotas.
- [x] Skip limit-list calls in regions with no relevant GPU quota names.
- [x] Skip hardware recipe/image rendering when no observation can cover even one whole host; retain local exclusion diagnostics.
- [x] Verify request counts, confirmed-only eligibility, consolidated output and extracted entry ZIP. No GPUs allocated or new live capacity scan run for this cleanup.

Verification: 14 CLI/report JavaScript tests, 10 inventory mocks, 24 allocation mocks, 46 planner mocks, 10 root mocks and 9 report tests passed. The packaged discovery root and both embedded template roots passed native validation with Terraform 1.5.7. Original discovery state and variable files are unchanged. No runtime-speedup percentage is claimed; tests establish reduced configured requests, not a production timing benchmark.
