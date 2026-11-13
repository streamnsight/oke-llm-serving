<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# GPU infrastructure and shared controllers

Use `terraform/stacks/infrastructure` with its own Terraform state. It creates **GPU node infrastructure only**, a shared DevOps project and an explicitly invoked platform bootstrap pipeline. Existing cluster CPU pools run shared controllers. No model, serving image, benchmark or discovery-JSON input is required. The older `deployment` root remains a combined implementation; do not apply both roots to create the same infrastructure. Separate model deployment and undeploy pipelines are deferred.

## Preview first

Copy `terraform/stacks/infrastructure/target.example.json` to an ignored local file. Fill in the tenancy/compartment, existing cluster, selected region, AD, GPU shape and host count from discovery. Keep `platform_name` stable across models and discovery runs. This first pass supports one platform owner per cluster.

```sh
terraform -chdir=terraform/stacks/infrastructure init
terraform -chdir=terraform/stacks/infrastructure plan -var-file="$PWD/work/infrastructure-target.json"
```

`provision_resources=false` is the default. Plan reads the cluster/network and compatible OKE GPU images; it creates no node pools, Compute Clusters, capacity-report resources or DevOps resources. Inspect `infrastructure_preview`. No CPU image is required or queried. Existing worker/pod subnets and NSGs are reused when unambiguous; overrides must remain in the cluster VCN. Empty RMS NSG lists preserve inherited policies rather than clearing them. Routing, DNS, security rules and HTTPS egress still require environment validation.

For RMS, run `make package-infrastructure` after committing changes and upload `work/packages/oke-llm-infrastructure.zip`, with working directory `.`. The normal form asks for a stable name, compartment (defaults to the stack compartment), existing cluster, GPU AD/shape/host count and provisioning switch. RMS supplies the region. Image, RDMA, disk and network settings are advanced controls. No large JSON variable is involved. Generated per-option ZIPs/launch links remain future work; enter the hardware choice from discovery for now.

## Provisioning boundary

Only after reviewing preview, enable `provision_resources=true` and run a new Plan. This creates a retained GPU pool and, for supported RDMA shapes/regions, a Compute Cluster and scoped launch policy. Auto mode falls back to Ethernet when Compute Cluster support is not cataloged for the shape/region; preview states that explicitly. An explicit unsupported RDMA request fails. Regional support metadata can lag service expansion and needs review when adding regions. Allocation checks target-compartment entitlement, OKE shape/image support and quantity-specific host capacity. A fresh capacity report is requested on each provisioning plan/apply unless an explicit observation ID is supplied. Counts are whole hosts. Reports do not reserve capacity or prove RDMA transport.

No CPU pool is created. Later model-local CPU services that need GPU colocation belong to the model deployment design. The 200 GiB boot-disk default is a baseline: increase it **before allocating hosts** for larger checkpoints/caches. It does not certify arbitrary model disk fit.

Do not rename an allocated platform, switch it back to preview or test teardown on scarce GPUs. Retained-pool safeguards remain enabled. `prevent_destroy` blocks Terraform pool destruction; it does not prevent every in-place update, upgrade or service-side cycling operation. No live GPU nodes were allocated, resized, cycled or deleted during this implementation.

## Bootstrap shared components

Terraform creates pipeline records but does not execute them. First, an existing cluster administrator applies the explicit bootstrap binding:

```sh
terraform -chdir=terraform/stacks/infrastructure output -json bootstrap_rbac > work/platform-bootstrap-rbac.json
kubectl apply -f work/platform-bootstrap-rbac.json
terraform -chdir=terraform/stacks/infrastructure output -json platform
```

Run the returned `bootstrap_pipeline_id` in OCI DevOps. It follows the [oke-langfuse Shell stage pattern](https://github.com/streamnsight/oke-langfuse/tree/main/modules/devops/deployment_stages/shell_stage): inline command spec, pipeline resource-principal authentication and private-endpoint kubeconfig. Its subnet must reach OKE, OCI, Kubernetes binary downloads and Helm registries. Administrator permissions belong to this shared bootstrap identity; later model identities require separate scopes. Serialize bootstrap runs for the same platform.

The pipeline:

1. Downloads checksum-verified kubectl and Helm clients.
2. Checks Ready, schedulable allocation nodes advertising the full GPU count per shape, and existing schedulable CPU nodes for LWS. RDMA requires an unambiguous advertised extended resource or an explicit existing resource name. These checks measure advertised capacity, not free GPUs or CUDA/NCCL operation.
3. Installs the LWS 1.0.0 chart with GPU shapes excluded from controller scheduling. The chart supplies images/defaults and bundled CRDs. Existing installations are reused read-only only when an identifiable, healthy release matches that chart version. Ownership/version ambiguity fails instead of adopting or upgrading controllers.
4. Waits for CRD establishment/controller rollout and submits a server-side dry run of a zero-replica LWS to check API/webhook admission. This persists no instance and schedules no model/probe pods.
5. Writes generation-specific readiness and per-run evidence to private Object Storage. Failures replace the in-progress marker with failed readiness.

GPU/network support stays OKE-owned. [These add-ons are optional](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengintroducingclusteraddons.htm): an enhanced cluster alone does not prove they are enabled. This pass inventories installed add-ons and checks actual node resources. It does not enable/upgrade missing GPU/network add-ons, install standalone operators or create RDMA network policies/attachments. Enable/configure required managed capabilities through OKE before bootstrap can pass. Legacy image-provided device plugins can also satisfy resource checks. Prometheus/KEDA are deferred until model metrics/scaling requirements are defined.

## Contract and validation

Terraform owns private `platform-spec.json` with selected hardware, image/network evidence and allocation identity. The small `platform` output gives pool, cluster, project and specification/readiness URIs. The pipeline exclusively owns `<platform>/<generation>/readiness.json`; Terraform never writes a runtime-success flag. Later model deployment must check its generation against the descriptor. Neither object contains credentials or the full discovery report.

Local checks cover GPU-only allocation, omitted CPU image lookup, preview guards, RDMA prerequisites, controller ownership and the complete Bash runner with mocked external commands. The released LWS chart is rendered locally. They do not establish live RMS form behavior, node allocation, IAM propagation, private connectivity, actual admission, CUDA or RDMA transport. Authenticated RMS preview and bootstrap on a selected target are next; GPU allocation requires a separate explicit decision.
