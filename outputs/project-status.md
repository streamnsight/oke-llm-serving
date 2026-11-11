# Project status

Updated November 11, 2026.

## Current direction

Two user-facing Resource Manager stacks: discovery from a public model URL and serving assumptions, followed by allocation/DevOps from an explicitly selected configuration. Existing OKE cluster first; retain scarce GPU allocations and scale serving inside them.

All model/OCI discovery now uses native Terraform providers and HCL. Python, Bash analyzers, external wrappers and the precomputed-profile path have been removed. No Terraform process launches another Terraform process. Older planning notes describing those paths are superseded.

## Phase 1 — discovery

- [x] Inspect Hugging Face model metadata through HTTP provider data sources and SHA-pin config reads.
- [x] Estimate conventional full-context KV and all resident MoE weights with explicit context/concurrency/runtime assumptions.
- [x] Label Hub-published counts as declared metadata and return unsupported/null estimates when evidence is insufficient.
- [x] Use native OCI shapes, limits, headroom and capacity reports, keeping root capacity separate from compartment entitlement.
- [x] Implement a single discovery root module and RMS input schema.
- [x] Use checked-in provider aliases and READY-subscription-driven module counts; reject unmapped selected regions.
- [x] Remove local region orchestration and all interpreter-based model paths.
- [x] Finish combined live stack validation and record current test results (18 Terraform test runs; single live plan/apply across 16 subscribed regions).
- [ ] Validate a real RMS job and input-form rendering.

Local model-only native apply succeeded for Qwen/Qwen2.5-0.5B-Instruct: 988,065,536 weight bytes and a 3.729 GiB aggregate estimate at 4096 tokens × four concurrent sequences, including assumed 2 GiB runtime and 20% margin. This is not a per-GPU fit or throughput measurement.

An initial live capacity investigation covered all 16 READY subscriptions and 26 ADs using native OCI reports. Five regions listed no GPU shapes; reported positive capacity existed in ten regions, with Chicago's listed shapes out of capacity. No GPU hardware was allocated. The combined single-state discovery stack also completed live validation; see the validation record and capacity report for the newer snapshot.

## Phase 2 — layout and deployment (not implemented)

- [ ] Add sourced GPU VRAM/topology catalog and per-rank fit/engine compatibility checks; expose candidate layouts and node quantities.
- [ ] Inspect the selected OKE cluster and existing allocation.
- [ ] Define the selected deployment specification: region, AD, cluster, shape, node count, pinned model/configuration and serving recipe.
- [ ] Provision retained GPU pool/compute cluster where supported and any CPU infrastructure.
- [ ] Provision OCI DevOps resources and deploy CRDs/operators, serving and API/conversation components.
- [ ] Validate inference and scaling inside the retained GPU allocation.

The first native metadata estimator supports public conventional-attention models only. Gated/private models, quantized/custom/multimodal estimates and model-specific serving recipes need additional implementation. Capacity is never a reservation or proof of RDMA placement. Root headroom does not prove a child compartment's entitlement.

See [RMS workflow](../docs/rms-discovery.md), [model-profile limitations](../docs/model-profile.md) and [deployment plan](oci-oke-model-deployment-plan.md).
