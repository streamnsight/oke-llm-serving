# Native Terraform OCI discovery

OCI inventory and capacity assessment now use only the oracle/oci Terraform provider and Terraform expressions. There are no OCI Python SDK calls, external programs, shell provisioners or OCI CLI dependencies. The old inventory, capacity and terraform-oci Python commands have been removed.

## Modules

| Module | Native constructs |
|---|---|
| accelerator-inventory | oci_identity_region_subscriptions, oci_identity_availability_domains, oci_core_shapes, oci_limits_limit_definitions, oci_limits_limit_values, oci_limits_resource_availability |
| capacity-assessment | oci_core_compute_capacity_report plus terraform_data for explicit report replacement |

Each module inherits its OCI provider from its caller. The caller supplies tenancy_ocid and a region label matching that provider. Credentials belong to the provider, not module variables or Python configuration. The example uses the local DEFAULT profile through the provider's normal authentication chain. Resource Manager supplies credentials to the OCI provider; its documented minimum provider configuration is region.

```hcl
provider "oci" {
  region = var.region
}

module "inventory" {
  source         = "../../modules/accelerator-inventory"
  tenancy_ocid   = var.tenancy_ocid
  region         = var.region
  compartment_id = var.compartment_id
  shape_names    = ["VM.GPU.A10.1"]
}
```

## Running the example

Use terraform/examples/oci-discovery. Set tenancy_ocid and region through your local uncommitted variable file or Resource Manager inputs. Resource Manager prepopulates those named variables in its Console workflow.

```sh
terraform -chdir=terraform/examples/oci-discovery init
terraform -chdir=terraform/examples/oci-discovery plan -var-file=/path/to/discovery.tfvars.json
terraform -chdir=terraform/examples/oci-discovery apply -var-file=/path/to/discovery.tfvars.json
```

Only data sources run unless availability_domain is set. Supplying that AD enables creation of a capacity report and a local Terraform bookkeeping resource. Neither allocates instances, reservations, Compute Clusters or node pools.

The provider is constrained to OCI 7.x and the tested example lock file pins 7.32.0. Other module callers should maintain their own lock files. Provider download, network access and IAM remain deployment requirements; avoiding external runtimes does not remove those dependencies.

## Inventory scope and output

The result schema is 2.0. It lists subscriptions, but one module instance scans one provider region. The old regions-list input is removed. For several regions, instantiate the module with explicit provider aliases or run one regional Resource Manager stack/job per selected subscribed region. Terraform does not dynamically instantiate provider configurations from subscription data.

Within the region, shapes are listed for every AD. shape_names filters GPU shapes; an empty set retains all visible GPU shapes. image_id optionally filters for image-compatible shapes. Returned fields include GPU count/description, host_memory_gb, OCPUs, local disk capacity and RDMA ports/bandwidth. GPU VRAM and NVLink topology remain null until catalog enrichment is implemented. A visible shape is not itself proof of OKE compatibility or launch capacity.

Limit definitions/values use the tenancy root. Shape lookup and resource availability use compartment_id, defaulting to root. Thus root entitlement observations do not prove a child compartment has the same entitlement or launch permissions.

Quota-name matching is exact. Limits retain their name, scope, tenancy limit, description, available/used values, fractional values and effective quota. No quota-to-instance conversion is inferred. Unmapped shape quota names remain visible.

Only limits whose metadata explicitly supports resource availability and whose scope can be resolved are queried. Regional/global queries omit AD; AD queries use the AD from the limit value. max_limit_checks bounds calls deterministically by sorted key. query_resource_availability=false disables all headroom calls. exclude_limit_names explicitly omits named queries. Skipped/unsupported/budget-limited headroom is unknown, not zero. A response without available/fractional availability also remains unknown. A null effective quota is not presented as unlimited capacity.

## API errors fail the plan

Native provider data sources fail Terraform on permission errors, unsupported API errors not reflected in metadata, transport failures and other API diagnostics. Terraform try() cannot catch these provider request failures. This differs from the removed SDK wrapper's partial-error JSON behavior.

Known unsupported queries are skipped using limit metadata. If an endpoint still fails, examine the provider diagnostic, correct IAM/scope or explicitly exclude that limit/disable headroom queries and rerun. The resulting omitted headroom remains unknown. A cross-region coordinator can run independent regional jobs to keep one region's error from preventing others from completing.

Successful outputs can still be complete or partial depending on omitted/null entitlement data. Complete means the selected observations were obtained, not that enough resources exist.

## Capacity snapshots and freshness

Capacity reports always use tenancy_ocid, not the target deployment compartment. Set availability_domain and shape_names; fault_domain is an optional report scope. requested_instances is compared per returned shape/FD row. Counts are instances rather than GPUs, and rows are never summed across scopes. Missing/invalid counts and HARDWARE_NOT_SUPPORTED remain unknown. OUT_OF_HOST_CAPACITY is a known negative result.

The OCI 7.x provider exposes available_count as a string. The module converts numeric values explicitly and treats unparseable values as unknown.

The module requires observation_id. Change it to create a new report through replace_triggered_by. Keeping it fixed preserves the report snapshot. An ordinary Terraform refresh is not a promise of a new physical-capacity observation. The example defaults to initial for convenience; a discovery pipeline should pass its unique run ID before each new assessment.

Before allocating hardware, request a fresh report again. A report is not a reservation, and available counts do not guarantee a subsequent launch or RDMA/Compute Cluster placement.

## Migration from schema 1.0 wrappers

- Remove the OCI SDK dependency and stop using the removed OCI Python commands and discover.py scripts.
- Replace profile/auth/python_executable module inputs with a caller-configured OCI provider and explicit tenancy_ocid/region.
- Replace regions lists with regional provider aliases or regional stack runs.
- Consume the result schema 2.0 directly; resource-availability fields are now directly inside the observation rather than a generic SDK data envelope.
- Capacity is now a Terraform-managed report created during apply. It cannot supply fresh computed capacity as if it had already been queried during the first plan.
- Changing observation_id replaces only the report and its local bookkeeping, not GPU instances.
- Old external data-source entries are removed from state on apply. They did not own allocated hardware. Do not remove unrelated infrastructure state.

## RMS and model analysis

OCI discovery requires no Python or Bash runtime beyond the Terraform provider execution environment. Hugging Face analysis is different: binary-header parsing, architecture interpretation, estimates and tests remain in Python. A shell rewrite would require its own HTTP/JSON/binary tooling and would not provide an unconditional reliability guarantee.

For RMS, generate model-profile JSON in a controlled, versioned build environment and supply it to the model-profile module's profile_json input. That path never executes Python. External analysis is disabled by default and requires explicit enable_external_analysis=true on a prepared runner. See terraform/examples/model-profile-rms and [model tool documentation](model-profile.md).

## Verification

Run Python model tests and Terraform native-provider tests:

```sh
PYTHONPATH=src python3 -m unittest discover -s tests -v
terraform -chdir=terraform/modules/accelerator-inventory init -backend=false
terraform -chdir=terraform/modules/accelerator-inventory test
terraform -chdir=terraform/modules/capacity-assessment init -backend=false
terraform -chdir=terraform/modules/capacity-assessment test
terraform -chdir=terraform/modules/model-profile init -backend=false
terraform -chdir=terraform/modules/model-profile test
```

Terraform's mock-provider tests require Terraform 1.7+; modules themselves require 1.5+. See the [validation record](../outputs/oci-discovery-validation.md) for live checks. Actual RMS execution, additional authentication modes and target-child-compartment checks remain to be validated there.

Sources: [Resource Manager requirements](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/terraformconfigresourcemanager.htm), [shape data source](https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/d/core_shapes.html), [resource availability](https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/d/limits_resource_availability.html), [capacity report resource](https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/r/core_compute_capacity_report.html).
