<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# GPU infrastructure and shared controllers

Use `templates/infrastructure` with its own Terraform state. It creates **GPU node infrastructure only**, a shared DevOps project and an explicitly invoked platform bootstrap pipeline. Existing cluster CPU pools run shared controllers. No model, serving image, benchmark or discovery-JSON input is required. The older `deployment` root remains a combined implementation; do not apply both roots to create the same infrastructure. Separate model deployment and undeploy pipelines are deferred.

Regional DevOps/storage/node resources use the selected deployment region. Dynamic-group and IAM-policy writes use a separate provider in the tenancy home region, discovered from OCI tenancy/region data. No home-region input or region mapping file is required; `infrastructure_preview.iam_home_region` shows the result.

## Preview first

Copy `templates/infrastructure/target.example.json` to an ignored local file. Fill in the tenancy/compartment, existing cluster, selected region, AD, GPU shape and host count from discovery. Keep `platform_name` stable across models and discovery runs. This first pass supports one platform owner per cluster.

```sh
terraform -chdir=templates/infrastructure init
terraform -chdir=templates/infrastructure plan -var-file="$PWD/work/infrastructure-target.json"
```

Use Terraform Plan to preview all changes without creating resources. Apply always creates the DevOps platform resources. Normally `skip_gpu_allocation=false` also allocates GPU hosts; temporarily set it to true for CPU-platform debugging. Debug mode creates no GPU node pools, Compute Clusters or GPU capacity-report resources. Inspect `infrastructure_preview`. No CPU image is required or queried. Existing worker/pod subnets and NSGs are reused when unambiguous; overrides must remain in the cluster VCN. Empty RMS NSG lists preserve inherited policies rather than clearing them. The form can serialize its blank row as `[""]`; blank, whitespace and null entries are ignored, while actual IDs are trimmed and deduplicated. Routing, DNS, security rules and HTTPS egress still require environment validation.

For RMS, use a launch URL from discovery's `deployment_options` after Apply; see [publication](infrastructure-publication.md). Hardware/storage defaults are already populated. Select an existing cluster and review preview; the compartment defaults to the stack compartment and RMS supplies its actual region. Image, RDMA, disk and network settings are advanced controls. No large JSON variable is involved. `make package-infrastructure` still builds an unconfigured standalone developer ZIP that requires entering the discovery hardware choice manually.

## Provisioning boundary

After reviewing Plan, Apply with `skip_gpu_allocation=false` creates a retained GPU pool and, for supported RDMA shapes/regions, a Compute Cluster and scoped launch policy. Auto mode falls back to Ethernet when Compute Cluster support is not cataloged for the shape/region; preview states that explicitly. An explicit unsupported RDMA request fails. Regional support metadata can lag service expansion and needs review when adding regions. Allocation checks target-compartment entitlement, OKE shape/image support and quantity-specific host capacity. A fresh capacity report is requested on each provisioning plan/apply unless an explicit observation ID is supplied. Counts are whole hosts. Reports do not reserve capacity or prove RDMA transport.

No CPU pool is created. Later model-local CPU services that need GPU colocation belong to the model deployment design. The 200 GiB boot-disk default is a baseline: increase it **before allocating hosts** for larger checkpoints/caches. It does not certify arbitrary model disk fit.

New pools set `node_metadata = { areLegacyImdsEndpointsDisabled = "true" }`. This is OKE launch metadata, not a free-form or defined tag. OKE uses it to disable IMDSv1 for new worker instances, including in tenancies that reject launches enabling legacy IMDS. The value is a string because node metadata is a map of strings. The shared allocation module's optional CPU pool also uses this default; infrastructure still creates GPU pools only.

### Existing CPU pool blocked by the tenancy IMDS rule

An error mentioning `instanceOptions.areLegacyImdsEndpointsDisabled: false` and `imds/imds-disable-v1` means the pool's launch configuration must disable IMDSv1. [Oracle documents updating node metadata through the CLI](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengconfiguringimds.htm). Preserve existing entries such as cloud-init user data when changing the metadata map:

```sh
pool_ocid="<existing CPU node pool OCID>"
imds_metadata_file=$(mktemp)
oci ce node-pool get --profile DEFAULT --region eu-frankfurt-1 \
  --node-pool-id "$pool_ocid" --query data |
  jq '(."node-metadata" // {}) + {"areLegacyImdsEndpointsDisabled":"true"}' \
  > "$imds_metadata_file"

oci ce node-pool update --profile DEFAULT --region eu-frankfurt-1 \
  --node-pool-id "$pool_ocid" \
  --node-metadata "file://$imds_metadata_file"
rm -f "$imds_metadata_file"
```

This changes future node launches and can allow a pool's pending nodes to be created. It does not retrofit existing instances or require destroying/recreating the pool. If Terraform manages that existing pool, record the same `node_metadata` setting in its owning configuration. The Compute Console's **Instance metadata service → Edit → Version 2 only** control edits an individual instance; use the pool setting for future OKE workers. The repository change does not modify an existing external CPU pool until its owner applies an update.

Do not rename an allocated platform, enable debug skipping after GPU allocation, or test teardown on scarce GPUs. Retained-pool safeguards remain enabled. `prevent_destroy` blocks Terraform pool destruction; it does not prevent every in-place update, upgrade or service-side cycling operation. No live GPU nodes were allocated, resized, cycled or deleted during this implementation.

## Bootstrap shared components

Terraform creates pipeline records but does not execute them. First, an existing cluster administrator applies the explicit bootstrap binding:

```sh
terraform -chdir=templates/infrastructure output -json bootstrap_rbac > work/platform-bootstrap-rbac.json
kubectl apply -f work/platform-bootstrap-rbac.json
terraform -chdir=templates/infrastructure output -json platform
```

Run the returned `bootstrap_pipeline_id` in OCI DevOps. It follows the [oke-langfuse Shell stage pattern](https://github.com/streamnsight/oke-langfuse/tree/main/modules/devops/deployment_stages/shell_stage): inline command spec, pipeline resource-principal authentication and private-endpoint kubeconfig. Its subnet must reach OKE, OCI, Kubernetes binary downloads and Helm registries. Administrator permissions belong to this shared bootstrap identity; later model identities require separate scopes. Serialize bootstrap runs for the same platform.

The pipeline policy includes both `compute-container-instances` and `compute-containers`, as required by [Oracle's Shell-stage IAM policy](https://docs.oracle.com/en-us/iaas/Content/devops/using/devops_iampolicies.htm), plus network, command-artifact, logging and platform-bucket access. Creating the pipeline does not itself grant Kubernetes RBAC: apply the generated binding as a cluster administrator before bootstrap installs CRDs.

The pipeline:

1. Downloads checksum-verified kubectl and Helm clients.
2. Checks existing Ready, schedulable CPU nodes for LWS. Normal mode also checks allocation nodes advertising the full GPU count per shape. Debug mode does not wait for or validate GPU/RDMA resources and records `validation_scope=cpu_components_only` plus `gpu_validation=skipped_debug`. RDMA requires an unambiguous advertised extended resource or an explicit existing resource name. These checks measure advertised capacity, not free GPUs or CUDA/NCCL operation.
3. Installs the LWS 1.0.0 chart with GPU shapes excluded from controller scheduling. The chart supplies images/defaults and bundled CRDs. Existing installations are reused read-only only when an identifiable, healthy release matches that chart version. Ownership/version ambiguity fails instead of adopting or upgrading controllers.
4. Waits for CRD establishment/controller rollout and submits a server-side dry run of a zero-replica LWS to check API/webhook admission. This persists no instance and schedules no model/probe pods.
5. Writes generation-specific readiness and per-run evidence to private Object Storage. Failures replace the in-progress marker with failed readiness.

GPU/network support stays OKE-owned. [These add-ons are optional](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengintroducingclusteraddons.htm): an enhanced cluster alone does not prove they are enabled. This pass inventories installed add-ons and checks actual node resources. It does not enable/upgrade missing GPU/network add-ons, install standalone operators or create RDMA network policies/attachments. Enable/configure required managed capabilities through OKE before bootstrap can pass. Legacy image-provided device plugins can also satisfy resource checks. Prometheus/KEDA are deferred until model metrics/scaling requirements are defined.

## Contract and validation

Terraform owns private `platform-spec.json` with selected hardware, image/network evidence and allocation identity. The small `platform` output gives pool, cluster, project and specification/readiness URIs. The pipeline exclusively owns `<platform>/<generation>/readiness.json`; Terraform never writes a runtime-success flag. Later model deployment must check its generation against the descriptor. Neither object contains credentials or the full discovery report.

Local checks cover GPU-only allocation, omitted CPU image lookup, preview guards, RDMA prerequisites, controller ownership and the complete Bash runner with mocked external commands. The released LWS chart is rendered locally. They do not establish live RMS form behavior, node allocation, IAM propagation, private connectivity, actual admission, CUDA or RDMA transport. Authenticated RMS preview and bootstrap on a selected target are next; GPU allocation requires a separate explicit decision.
