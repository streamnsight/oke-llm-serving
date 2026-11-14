<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Native regional inventory and allocation admission

The entry discovery stack uses the single dynamic OCI CLI scanner described in [RMS discovery](rms-discovery.md). These native Terraform modules serve the later allocation check and the standalone `examples/oci-discovery` example. They do not run alongside the CLI scanner in the discovery state.

| Module | Purpose |
|---|---|
| `accelerator-inventory` | Shape metadata, configured limits and effective compartment headroom |
| `capacity-assessment` | Quantity-specific physical capacity report; no hardware allocation |

Both inherit the caller's OCI provider, constrained to `~> 9.12`, and accept a matching region label. Credentials belong to the provider. The local DEFAULT profile and Resource Manager authentication use the provider's normal authentication chain.

```hcl
provider "oci" { region = var.region }

module "inventory" {
  source              = "../../modules/discovery/accelerator-inventory"
  tenancy_ocid        = var.tenancy_ocid
  compartment_id      = var.compartment_id
  region              = var.region
  availability_domain = var.availability_domain
  shape_names         = ["VM.GPU.A10.1"]
}
```

The native inventory never lists region subscriptions. With an explicit `availability_domain`, it skips AD discovery and queries shapes only in that AD. Omitting the AD inventories all ADs within the inherited provider region. The allocation module supplies its selected AD and shape, so it does not repeat the earlier all-region scan.

Shape and headroom queries use the target compartment; limit definitions/values use the tenancy root. Only quota names attached to visible selected GPU shapes are considered. AD limits are restricted to the selected AD; applicable regional/global limits remain included. Shared quota/scope keys are queried once. Unsupported, excluded or budget-limited observations remain unknown and cannot establish sufficient entitlement.

Returned GPU VRAM comes from the sourced shape catalog. Host RAM is a separate field; unknown GPU VRAM or topology remains null. Shape visibility alone does not establish OKE support or available hardware. Allocation also checks the selected image, cluster, add-ons and transport requirements.

## Fresh capacity before allocation

`capacity-assessment` creates an OCI diagnostic report and local Terraform bookkeeping, with no instances, node pools, reservations or Compute Clusters. It reports counts of hosts, not GPUs. Reports use the tenancy root and the explicit AD/shape, optionally a fault domain. Missing or unparseable counts remain unknown; `OUT_OF_HOST_CAPACITY` is a negative result.

Changing `observation_id` replaces the native report. Keeping it fixed preserves that report resource's snapshot. This differs from the entry CLI scanner, which runs when Terraform reads its external data source; its observation ID is a label rather than a cache switch.

Allocation admission compares fresh physical capacity and GPU entitlement against additional whole hosts, accounting for retained hosts. Rechecking the selected target is deliberate: discovery did not reserve capacity, and deployment inputs may have changed. Even a positive report cannot guarantee the later launch or RDMA placement.

Provider permission, transport and API errors fail the Terraform operation. They do not become zero counts or successful partial scans. Skipped/unsupported observations can still produce an explicitly partial inventory, which does not establish launch eligibility.

## Local verification

```sh
terraform -chdir=modules/discovery/accelerator-inventory init -backend=false
terraform -chdir=modules/discovery/accelerator-inventory test
terraform -chdir=modules/discovery/capacity-assessment init -backend=false
terraform -chdir=modules/discovery/capacity-assessment test
```

Mock-provider tests require Terraform 1.7+; deployment configurations support Terraform 1.5+. Tests do not allocate hardware. See [RMS discovery](rms-discovery.md) for the single output contract and quota/capacity diagnostics.

API references: [shape data source](https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/d/core_shapes.html), [resource availability](https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/d/limits_resource_availability.html), [capacity report](https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/r/core_compute_capacity_report.html).
