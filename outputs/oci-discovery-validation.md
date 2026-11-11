# Native Terraform discovery validation

Validated November 11 2026 using the local DEFAULT OCI provider credentials.

## Current implementation

The earlier OCI SDK/external-program implementation has been replaced. OCI inventory uses native provider data sources; capacity uses oci_core_compute_capacity_report with an explicit observation identifier. No Python SDK, OCI CLI or Bash program runs in the OCI discovery path.

## Completed checks

- 16 Python model-analysis tests passed.
- 5 Terraform inventory test runs passed with mocked provider responses, covering scope separation, GPU filtering, unsupported limits, bounded queries, exclusions and unmapped quota names.
- 5 Terraform capacity test runs passed, covering instance counts, unsupported hardware, known zero capacity, invalid counts and observation identifiers.
- 4 Terraform model-profile test runs passed, including runtime-free input and explicit opt-in for external analysis.
- Terraform formatting and configuration validation passed.
- Live native-provider inventory completed against the DEFAULT region, us-chicago-1, with three AD-scoped A10 resource-availability queries.
- Native Terraform plan/apply created only a capacity report and a Terraform bookkeeping resource; no GPU hardware was allocated.
- The native capacity report returned OUT_OF_HOST_CAPACITY and zero instances for VM.GPU.A10.1 in the selected AD.
- A repeated plan preserved the existing capacity snapshot without changes to managed resources. Changing observation_id planned replacement of only the report and local bookkeeping resource.
- A local plan/apply of the runtime-free model-profile example succeeded using a precomputed model profile; no external Python data-source instance was created. The opt-in local Python example also passed a fresh live plan/apply.

The tested OCI provider version is 7.32.0 and Terraform version is 1.9.8. Native discovery result schema is 2.0. Test fixtures are not measurements of OCI capacity.

## Snapshot and scope

Physical-capacity observations are tied to the report's time_created, region, AD and optional FD. Change observation_id for a fresh assessment. Neither report success nor quota headroom guarantees successful instance allocation or RDMA placement.

Tenancy/AD identifiers and full live outputs remain in ignored local artifacts and state, not in committed examples. The root-level quota check does not prove eligibility inside a target child compartment.

## Remaining validation

- Run the native stack and precomputed-model flow in OCI Resource Manager itself.
- Validate additional provider authentication modes and child-compartment policies.
- Validate other regions, shapes and RDMA-specific placement.
- Provision and test actual GPU nodes in subsequent deployment milestones.

External Python execution is disabled by default. A prepared local/build runner may opt in, but no guarantee is made about Python availability on managed RMS hosts.
