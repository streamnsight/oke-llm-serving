# OCI OKE deployment project status

Updated November 11 2026

## Current status

Research and architecture planning are documented. The user has accepted the proposed direction. No model-inspection implementation, Terraform infrastructure modules or DevOps deployment pipelines have been built or deployed yet.

## Documents

- [Deployment plan](oci-oke-model-deployment-plan.md)
- [Serving ecosystem report and production-stack investigation](kubernetes-llm-serving-report.md)

## Decisions recorded

- Start with an existing regional OKE cluster.
- Begin with Hugging Face model inspection, including architecture and weight/runtime/KV memory estimates with explicit assumptions.
- Expose the inspection tool through a Terraform data-only wrapper where runner compatibility permits.
- Discover entitlement headroom and physical capacity separately. Use CreateComputeCapacityReport before allocation, preserving observation timestamps and unknown states.
- Support an RDMA managed-node-pool path using an OCI Compute Cluster on supported hardware and an enhanced OKE cluster.
- Consider a regular managed node pool when RDMA is unavailable only if the alternative remains feasible. Freeze the selected topology before apply.
- Terraform owns infrastructure and DevOps resource definitions. DevOps deploys cluster components and model releases.
- Retain allocated GPU nodes and scale serving within the allocation.
- Separate shared bootstrap, discovery and per-deployment allocation responsibilities; not every pipeline stage needs a separate Terraform stack.
- Keep outputs and configuration selections explicit and versioned between discovery and deployment.

## Next work package

- [ ] Inspect workspace/repository conventions before implementation.
- [ ] Define the model-profile input/output schema and confidence/provenance fields.
- [ ] Implement Hugging Face metadata and checkpoint inspection without executing repository code.
- [ ] Implement supported weight and KV estimators with explicit context/concurrency inputs.
- [ ] Add a Terraform external-data-source wrapper with a packaged runtime contract.
- [ ] Verify representative dense/MoE profiles, duplicate checkpoint variants, gated access and unsupported architectures.
- [ ] Document local execution and Resource Manager compatibility requirements.

OCI inventory and capacity assessment follow this package. Allocation and deployment modules consume the validated discovery contracts afterward.

## Decisions still to finalize

- Exact initial model/architecture coverage and validation models.
- First serving deployment recipe and pinned versions.
- Whether multi-node deployment and durable Responses conversation state are first-release requirements or subsequent increments.
- Target tenancy, compartment and cluster for integration testing.
- Packaging of the discovery runtime in Resource Manager versus a DevOps discovery job.

These decisions do not prevent documenting and designing the model-profile contract.
