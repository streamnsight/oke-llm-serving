<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Discovery presentation and model deployment workflow

Status: implementation in progress. This feature builds on the CPU-validated component foundation. GPU allocation, pool resizing/cycling/deletion and model workload execution are not authorized for validation. Preserve the user's staged AGENTS.md and untracked discovery review.

## Outcome and boundaries

Users discover an open-weight model, compare every capacity-confirmed deployment choice, provision or reuse retained infrastructure, and create a separate model-only DevOps deployment. An expert can adjust generated defaults and pipeline parameters. Operators can validate, benchmark and undeploy a model without changing GPU pools, shared controllers, project or model data.

The current pass must create the model stack and its pipeline resources in RMS without GPUs. Actual CUDA/NCCL, GPU placement, inference, cache transfer, routing behavior and throughput remain pending hardware validation. Terraform Apply creates delivery resources; it does not automatically execute model deployment.

## Architecture and choices

- Organize modules under discovery, infrastructure, cluster-add-ons, llm-deployment and shared. Retain relative module addressing and root-level main.tf in every published ZIP. Module movement must preserve Terraform resource addresses.
- Expose one compact model/capacity/options report with complete per-option PAR and RMS links; keep detailed diagnostics behind an explicit flag. Remove obsolete large inline JSON handoffs. Capacity counts are shape/AD observations, never a sum across alternative shapes or shared quotas.
- Separate available host/GPU counts, required GPUs per replica, allocated host/GPU counts and packed serving replicas. Memory fields retain source, units and unknown values.
- Model deployment reuses cluster, retained allocation selector, DevOps project, OKE environment and Generic Artifact repositories. It owns model release/pipelines and narrowly scoped delivery IAM, with no Compute/node-pool management.
- Compare upstream production-stack Helm and a small model workload chart before implementation. Prefer native Helm for model charts and readable artifact-backed Shell stages for preparation, validation, vLLM benchmarking and guarded teardown. Preserve frozen recipe argv/environment as data.
- A vLLM operator is optional, not required on top of Deployment/LWS. Gateways/routes, model cache instances, ServiceMonitors and ScaledObjects have model lifecycle; shared gateway controllers remain infrastructure capabilities when needed. Durable Responses/conversation storage is an API/data layer, separate from KV cache reuse.
- LMCache local RAM/disk needs no database by default; distributed/external tiers require explicit compatible service/storage configuration. Never infer a backend solely from the presence of a connector flag.
- Publish an infrastructure-bound model ZIP using the selected model/recipe and actual infrastructure outputs. Embed editable HCL/schema defaults rather than a large RMS JSON variable. No secrets enter bundles or pipeline parameters.

## Phases and verification

1. [ ] Reorganize module/template paths and document ownership. Verify relative references, Terraform roots and package closure; commit this mechanical change independently.
2. [ ] Replace redundant discovery output with compact model summary and all confirmed option rows, including links and supply/allocation/replica/memory distinctions. Test unavailable/unknown exclusions, AD granularity, units and correct total-GPU ranking.
3. [ ] Build model-only configuration/chart and artifact-backed deploy/validate/benchmark/undeploy pipelines. Test recipe argument preservation, single-node/replica/LWS renderings, namespace/ownership, retained data and no infrastructure resources/permissions.
4. [ ] Bind and publish the model stack from infrastructure with matching editable defaults, existing-project/environment/repository references and small RMS input requirements. Validate extracted root ZIPs and configured defaults.
5. [ ] Run Terraform/script/render/package checks and RMS Plan/Apply for pipeline creation only. Programmatically reject pool, Compute, reservation or shared-platform destruction; do not run model deployment/benchmark pipelines.
6. [ ] Document exact supported adapters, missing infrastructure/model/API capabilities and validation limits; clean generated development assets, commit feature changes and preserve user edits. Main integration requires the relevant end-to-end validation.
