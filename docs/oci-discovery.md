# OCI accelerator inventory and capacity assessment

This milestone adds two independent observations: GPU shape/entitlement inventory and physical host-capacity reports. It does not create instances, reservations, Compute Clusters or node pools. The capacity command does invoke CreateComputeCapacityReport, which creates a report without allocating hardware.

## Installation and authentication

Python 3.11+ is required. OCI discovery requires the optional OCI SDK dependency; Hugging Face inspection remains dependency-free.

```sh
python3 -m pip install -e '.[oci]'
```

Use a virtual environment for installation where appropriate. From the source checkout, `PYTHONPATH=src python3 -m oke_llm_serving ...` also works if the SDK is already installed in that interpreter.

Default authentication uses the DEFAULT profile in the standard OCI configuration file. Use `--profile` and `--config-file` to select another configuration. Resource-principal and instance-principal modes are available through `--auth`; supply the tenancy ID when the signer cannot derive it. Inventory can take its bootstrap region from `--regions`; capacity takes an explicit region. Local security-token session authentication is not yet a separate supported mode.

Keep keys/tokens out of Terraform variables and configuration artifacts. SDK errors are returned as sanitized status/code observations rather than raw request headers or service messages.

## Inventory

```sh
PYTHONPATH=src python3 -m oke_llm_serving inventory \
  --profile DEFAULT --shapes VM.GPU.A10.1
```

The initial scan uses only the profile's configured region. All subscribed regions are listed, but they are not all scanned automatically. To scan more, supply `--regions region-one region-two`. Requested regions not READY in the subscription list are marked not_ready_or_unsubscribed and skipped. If subscription enumeration is denied, explicitly requested regions are still attempted, with partial coverage recorded.

The inventory lists availability domains, then lists GPU shapes visible in the target compartment per AD. It retains GPU counts/descriptions, host memory, OCPUs, local disk capacity and RDMA ports/bandwidth. GPU VRAM and NVLink topology remain null: those require a separate sourced hardware catalog and must not be inferred from host RAM or marketing names.

Supply `--compartment-id` for the intended deployment compartment. When omitted, resource availability is queried at the tenancy root and the report records that scope. Root headroom does not establish that a child compartment has equivalent quota or permissions.

Limit definitions and values are queried at the tenancy root. Resource availability is queried in the selected target compartment. AD-scoped limits include the corresponding AD; regional/global calls omit AD. API-provided quota names are matched exactly to limit names. An unmatched name is recorded, not guessed from shape strings. The tool does not convert quota units into a number of deployable GPU instances.

The availability data retains available, used, fractional_availability, fractional_usage and effective_quota_value. A null effective quota is not presented as unlimited capacity. Raw quota-policy statements and inherited policy syntax are not independently parsed; the tool relies on the service's effective resource-availability result where supported.

Without a shape filter, GPU-named compute limits are also included as context. With a shape filter, only exact quota-name matches are checked. `--max-limit-checks` bounds availability calls across the entire run; default 100. A budget of zero lists shapes/limits without querying headroom and records those checks as unknown.

## Physical host capacity

```sh
PYTHONPATH=src python3 -m oke_llm_serving capacity \
  --profile DEFAULT --region REGION \
  --availability-domain 'FULL-TENANCY-SPECIFIC-AD-NAME' \
  --shapes VM.GPU.A10.1 --requested-instances 2
```

Use the full AD name from inventory. Optional `--fault-domain` scopes the report; it is not a recommendation to set fault-domain placement on an OKE Compute Cluster pool.

There is intentionally no deployment compartment input. The report always uses the root tenancy derived from authentication. A shape count is a count of instances, not GPUs. Each requested shape gets one or more scoped rows. Fault-domain rows are preserved separately and never summed across potentially overlapping scopes.

| Capacity observation | reported_sufficient |
|---|---|
| AVAILABLE with a nonnegative count | Comparison with requested_instances |
| OUT_OF_HOST_CAPACITY | false |
| HARDWARE_NOT_SUPPORTED | null; unsupported observation is not treated as a permanent absence of hardware |
| Missing shape/count, denied API or unknown status | null |

Reports are timestamped and not reservations. Counts can change before allocation, and they do not establish successful RDMA/Compute Cluster placement. Every Terraform data-source refresh requests a new report, rather than reusing a stored report as if it were fresh. Recheck again before eventual allocation.

## Result and error contract

Both operations return schema_version 1.0. Top-level status is complete or partial. Each API observation contains status observed or unknown, observed_at, data, and sanitized error status/code on request failure. Inventory also records the target compartment and region-by-region coverage.

Complete means the requested observations were obtained, not that capacity is sufficient. Zero headroom and OUT_OF_HOST_CAPACITY are valid known observations. Permission errors, unsupported availability APIs, missing fields, unresolved quota-name mappings and exhausted query budgets produce partial results instead of fabricated zeroes.

API observations that fail do not abort successful observations from other regions/ADs. Authentication/input errors are fatal, write structured JSON to stderr and exit 2. Partial discovery returns JSON and exit 0 so a planner can inspect the evidence. A deploying caller must explicitly check both completeness and sufficiency rather than treating exit 0 as permission to allocate.

Calls are sequential, SDK retries are disabled, and client timeouts are connection 10/read 30 seconds. API pagination is handled by the SDK. Explicit region selection and a headroom-query budget keep scope visible. Reports may contain tenancy/compartment IDs and operational capacity details; store them according to the tenancy's access policy. Live test artifacts are kept in ignored work/ and Terraform state is ignored.

## Terraform modules

- `terraform/modules/accelerator-inventory` returns `result` with inventory and entitlement observations.
- `terraform/modules/capacity-assessment` returns `result` with a freshly created capacity report and normalized shape rows. It accepts no deployment compartment.
- `terraform/examples/oci-discovery` demonstrates both. Capacity is disabled until availability_domain is set; set capacity_region at the same time.

```sh
terraform -chdir=terraform/examples/oci-discovery init
terraform -chdir=terraform/examples/oci-discovery plan
terraform -chdir=terraform/examples/oci-discovery apply
```

The wrappers use hashicorp/external, require the full repository source layout and require the OCI SDK in the selected Python executable. All query values are strings and the result is a string map containing result_json, decoded into a Terraform object by the module. These modules have no OCI allocation resources. Data observations and errors become part of Terraform state on apply.

For Resource Manager, package the source and SDK dependencies and configure an appropriate resource principal. Managed-runner execution and principal authentication have not yet been live-validated; local DEFAULT profile execution has. Deploying from a different compartment requires its own scoped eligibility check.

## Validation and remaining scope

Tests cover quota/target scope, AD/regional handling, pagination invocation, null/fractional availability, permissions, query budgets, unsupported capacity, FD count preservation, real SDK request serialization and subprocess entry points. Live validation uses the local DEFAULT profile without allocating instances. See [validation record](../outputs/oci-discovery-validation.md).

This is not yet the complete deployment planner. Remaining work includes the sourced GPU-memory/topology catalog, OKE cluster and existing-node allocation inspection, image compatibility, model-to-shape planning and infrastructure provisioning. The current result never claims that listing a shape proves it is OKE-compatible.

Primary references: [LimitsClient](https://docs.oracle.com/en-us/iaas/tools/python/latest/api/limits/client/oci.limits.LimitsClient.html), [ResourceAvailability](https://docs.oracle.com/en-us/iaas/tools/python/latest/api/limits/models/oci.limits.models.ResourceAvailability.html), [capacity-report root scope](https://docs.oracle.com/en-us/iaas/tools/python/latest/api/core/models/oci.core.models.CreateComputeCapacityReportDetails.html).
