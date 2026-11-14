<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Discovery HTML report

## Outcome

Make a self-contained Object Storage HTML report the discovery stack's only RMS output, exposed as a schema link. Present Hugging Face identity/architecture/checkpoint metadata, memory estimates for the requested workload, collapsed deployment options with recipe/configuration and stack links, and regional capacity/limit evidence even when no option is viable. Reuse existing discovery data; do not add scans or allocate GPUs.

User direction: each model owns an independent DevOps project and pipelines while reusing the GPU pool and shared components. Discovery publishes both configured ZIPs up front. The model stack asks for an existing cluster and optional pool; known bindings are resolved through native OCI data, while missing pool/component readiness is deferred to pipeline execution. Project creation must work before infrastructure deployment. Trusted cross-project onboarding grants only the exact model principals their namespace permissions after components exist. No GPU resource ownership is introduced in the model state.

## Phases

1. [x] Extend the internal report data with existing model dimensions/checkpoint formats, workload assumptions, selected serving evidence and regional entitlement/limit diagnostics. Preserve unknown values, exact-shape/AD scope and configuration-validation labels.
2. [x] Build the accessible report using the supplied Redwood tokens/shell styles, native collapsed option sections, memory/model sections, deployment links and bottom capacity table. Escape untrusted metadata and commands as text; allow HTTPS links only.
3. [x] Publish the report alongside bundles for all successful assessments, including zero-option and bundle-publication-disabled cases. Retain exactly one typed link output; keep JSON as embedded report data.
4. [x] Publish independent model ZIPs during discovery; give each model its own project/environment/artifact repositories and pipelines, native cluster/network/pool lookup, and runtime binding/readiness. Preserve trusted namespace onboarding with explicitly selected cross-project principals. Mocked creation succeeds before GPU allocation; live RMS validation follows below.
5. [ ] Test data/eligibility/links, empty/unknown/limit cases and output/schema contracts. Inspect desktop/mobile rendering and option interactions in a browser. Validate packaged Terraform with RMS-compatible Terraform; do not touch GPU allocations.
6. [ ] Update documentation, record validation, clean generated development assets, commit and integrate after scoped validation. Preserve user-owned AGENTS.md staging and the separate discovery review; never modify local discovery state/tfvars.

## Edge cases

- No confirmed choices must still yield a useful page and working report URL.
- Partial AD coverage, overlapping shape supply and unknown capacity must not become invented regional totals.
- A positive capacity report plus a zero limit may justify reviewing a limit increase; it does not prove the model or runtime will fit. State unknown/heuristic model fit explicitly.
- The displayed command must distinguish the adapted planned TP/PP/workload from the original upstream recipe command, especially when rendering used another GPU family.
- Expired PARs, missing publication links and model stacks awaiting infrastructure must have clear states without fake clickable links.
- Keep large detailed evidence opt-in. Styles, scripts and data are embedded; opening the report makes no additional discovery requests.
