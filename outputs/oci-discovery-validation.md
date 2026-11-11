# OCI discovery validation

Validated November 11 2026 using the local DEFAULT profile.

## Completed checks

- 36 unit/integration-contract tests passed, including the existing Hugging Face tests.
- Terraform formatting and configuration validation passed.
- Live OCI SDK inventory queried subscriptions, ADs, GPU shapes, compute limit metadata and target resource availability.
- Live capacity assessment invoked CreateComputeCapacityReport using the root tenancy.
- Terraform plan/apply completed with both accelerator-inventory and capacity-assessment external wrappers.
- The resulting Terraform outputs were checked for completeness and matching tenancy-root report scope.
- The existing model-profile Terraform example still validates.

## Observations

The configured region was us-chicago-1. Shape discovery listed BM.GPU.A10.4, VM.GPU.A10.1 and VM.GPU.A10.2 in one inspected AD. The filtered VM.GPU.A10.1 inventory completed three AD-scoped resource-availability checks for gpu-a10-count.

The host-capacity report for VM.GPU.A10.1 in the selected AD returned OUT_OF_HOST_CAPACITY with an available instance count of zero. This is a successful query with a known negative result, not an API failure. It is a timestamped observation for that scope, not a claim that all regions or GPU shapes lack capacity.

No instances, reservations, node pools or Compute Clusters were allocated. Capacity reports were created. Tenancy/AD identifiers and full live outputs remain in ignored work/ and local Terraform state, rather than in committed examples.

## Remaining validation

- OCI Resource Manager runner packaging and private networking.
- Resource-principal and instance-principal authentication against live OCI.
- Target-child-compartment quota/permission behavior against live OCI; automated tests cover scope separation.
- Additional shapes/regions and RDMA-specific placement evaluation.
- Node-pool provisioning and GPU runtime tests, which belong to later milestones.
