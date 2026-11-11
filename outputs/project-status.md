# OCI OKE deployment project status

Updated November 11 2026

## Current status

Model inspection and native Terraform OCI discovery are implemented. Python remains only for Hugging Face analysis. RMS can consume precomputed model profiles without Python execution; the native OCI modules require no external scripts. Live local-provider validation is complete; actual RMS and private/gated model execution remain pending.

## Documents

- [Deployment plan](oci-oke-model-deployment-plan.md)
- [Serving ecosystem report and production-stack investigation](kubernetes-llm-serving-report.md)

## Decisions recorded

- Start with an existing regional OKE cluster.
- Begin with Hugging Face model inspection, including architecture and weight/runtime/KV memory estimates with explicit assumptions.
- Use native OCI Terraform discovery. Feed precomputed model profiles into RMS; external model analysis is opt-in on prepared runners.
- Discover entitlement headroom and physical capacity separately. Use CreateComputeCapacityReport before allocation, preserving observation timestamps and unknown states.
- Support an RDMA managed-node-pool path using an OCI Compute Cluster on supported hardware and an enhanced OKE cluster.
- Consider a regular managed node pool when RDMA is unavailable only if the alternative remains feasible. Freeze the selected topology before apply.
- Terraform owns infrastructure and DevOps resource definitions. DevOps deploys cluster components and model releases.
- Retain allocated GPU nodes and scale serving within the allocation.
- Separate shared bootstrap, discovery and per-deployment allocation responsibilities; not every pipeline stage needs a separate Terraform stack.
- Keep outputs and configuration selections explicit and versioned between discovery and deployment.

## Completed first work package

- [x] Inspect workspace/repository conventions before implementation.
- [x] Define the model-profile input/output schema and confidence/provenance fields.
- [x] Implement Hugging Face metadata and checkpoint inspection without executing repository code.
- [x] Implement supported weight and KV estimators with explicit context/concurrency inputs.
- [x] Add a Terraform external-data-source wrapper with a packaged runtime contract.
- [x] Verify dense/MoE fixtures, duplicate checkpoint variants, simulated gated-access failures and unsupported architectures, plus live public dense-model inspection.
- [x] Document local execution and Resource Manager compatibility requirements.

See [model tool usage](../docs/model-profile.md) and [live example profile](example-model-profile.json).

## Completed native OCI discovery refactor

- [x] Replace the OCI SDK implementation with native Terraform data sources and a capacity-report resource.
- [x] Remove OCI SDK dependencies, Python commands and external wrapper scripts.
- [x] Keep tenancy-root capacity reporting separate from target-compartment entitlement queries.
- [x] Add explicit observation IDs for report freshness and document native provider fail-fast errors.
- [x] Default model-profile Terraform to runtime-free precomputed JSON; external Python analysis requires explicit opt-in.
- [x] Validate 16 Python tests and 14 Terraform test runs, plus live DEFAULT native-provider plan/apply and local runtime-free profile plan/apply.

The live VM.GPU.A10.1 query returned OUT_OF_HOST_CAPACITY in the inspected AD. No hardware was allocated. See [native OCI usage](../docs/oci-discovery.md) and [validation record](oci-discovery-validation.md). Actual RMS execution remains pending.

Next: source the GPU VRAM/topology catalog, inspect OKE compatibility/existing allocation, and combine these observations with model profiles to propose configurations. Allocation and DevOps deployment follow validated candidate planning.

## Decisions still to finalize

- Exact initial model/architecture coverage and validation models.
- First serving deployment recipe and pinned versions.
- Whether multi-node deployment and durable Responses conversation state are first-release requirements or subsequent increments.
- Target tenancy, compartment and cluster for integration testing.
- Packaging of the discovery runtime in Resource Manager versus a DevOps discovery job.

These decisions do not prevent documenting and designing the model-profile contract.
