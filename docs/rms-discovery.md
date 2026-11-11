<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

# Resource Manager workflow

The user-facing workflow has two stacks. The implemented first stack is `terraform/stacks/discovery`. The second stack, for allocation and DevOps, is subsequent work. An RMS job never invokes another Terraform process.

## 1. Discovery

Use the full repository as the RMS configuration source and set its working directory to **terraform/stacks/discovery**. Relative module paths require the full repository. Use a current RMS Terraform version compatible with the configuration (`>= 1.5`); local tests use Terraform 1.9.8. `schema.yaml` supplies the RMS input form; its Console rendering has not yet been tested.

User inputs:

- Public Hugging Face model URL, model revision, context tokens and concurrency.
- Optional KV dtype, runtime allowance and memory margin.
- Capacity observation identifier; change it to request new reports.
- Optional intended deployment compartment for quota headroom. Root headroom does not establish entitlement in a child compartment.

RMS supplies `tenancy_ocid` and the stack's `region`. That region is a bootstrap for subscription lookup, not the user's final GPU deployment region. Local execution uses the DEFAULT profile.

One plan reads the model through native HTTP data sources, enumerates READY subscriptions, lists GPU shapes in their ADs, and reads compute limits and supported resource-headroom APIs. Apply creates **capacity report resources and Terraform bookkeeping only**. It allocates no instances, node pools, clusters or DevOps resources. Host capacity values are available after apply, not just plan.

```sh
terraform -chdir=terraform/stacks/discovery init
terraform -chdir=terraform/stacks/discovery plan -var-file=/path/to/request.tfvars.json -out=/path/to/discovery.tfplan
terraform -chdir=terraform/stacks/discovery apply /path/to/discovery.tfplan
terraform -chdir=terraform/stacks/discovery output -json discovery
```

Example request (substitute your root OCID):

```json
{
  "tenancy_ocid": "YOUR_TENANCY_OCID",
  "region": "us-chicago-1",
  "model": "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct",
  "context_length": 4096,
  "concurrency": 4,
  "observation_id": "assessment-001"
}
```

`discovery` includes the model profile, all READY subscriptions, selected regions, per-region inventory and AD capacity reports. Consumers must check model estimate status, inventory status, unmatched quota names, capacity status and timestamps. A region with no visible GPU shapes is **not** treated as proof of physical capacity zero.

Native Terraform errors fail the job. There is no shell workaround that catches API errors and returns an apparently complete assessment. For troubleshooting, `regions` and `shape_names` accept explicit subsets and `query_resource_availability` can disable headroom calls; outputs record which regions were selected. RMS access needs tenancy subscription/AD visibility, relevant shape/limit/headroom permissions and capacity-report creation permission in root. Authentication/network failure is not a capacity observation.

### Regional provider constraint

Classic Terraform configurations cannot create provider aliases dynamically from a data-source result or select a provider through an expression. `regions.tf` therefore contains checked-in OCI regional aliases and module calls, with subscription-driven counts. The catalog covers public OC1 regions in the reviewed Oracle catalog/SDK, including the subscribed Chennai/Delhi endpoints. New/dedicated/other-realm regions require explicit catalog additions. A selected subscription absent from the catalog **fails** discovery instead of being silently skipped.

The static catalog is authored before execution. No generator runs in RMS, and no external data source launches Terraform. HashiCorp Terraform Stacks' dynamic-provider feature is a different product and is not assumed here.

### Freshness and interpretation

Reusing `observation_id` preserves existing report resources. Changing it replaces reports to obtain a fresh observation. Report counts are instances, not GPUs. FD alternatives must not be summed, and different shapes may draw from overlapping host capacity. Reported capacity is a snapshot, not a reservation, launch guarantee or proof of RDMA placement feasibility. Node capacity must be acquired/retained in the later allocation step.

The initial model path trusts Hub-published dtype counts and supports public models only. Host shape memory is not GPU VRAM. This stack exposes evidence; it does not yet generate validated model-to-shape layouts or recommended node quantities. VRAM/topology catalog enrichment, per-rank fit and serving-engine checks remain required before selecting quantities.

## 2. Allocation and DevOps (planned)

The user selects region, AD, existing OKE cluster, GPU shape and **node quantity** using discovery evidence and the forthcoming layout assessment. Keep node count, GPUs per node and total GPUs distinct. Pass the pinned model SHA and context/concurrency assumptions as well.

The deployment stack will validate cluster/shape/topology compatibility, create the retained node pool or RDMA compute-cluster-backed pool where supported, and create the DevOps resources. DevOps then deploys cluster components/CRDs, serving frameworks and API components and validates inference. It must not auto-deploy merely because discovery found capacity.

The stack-to-stack boundary uses explicit selected inputs or a versioned deployment specification. Initially the user transfers the selection; later a coordinator can read completed RMS job outputs. RMS does not automatically wire every output to another stack, and discovery does not provision the deployment stack recursively.

References: [Terraform provider configuration](https://developer.hashicorp.com/terraform/language/providers/configuration), [providers in modules](https://developer.hashicorp.com/terraform/language/modules/develop/providers), [RMS registry sourcing](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/providers.htm), [RMS job outputs](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/list-job-outputs.htm).
