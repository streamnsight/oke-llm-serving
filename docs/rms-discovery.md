<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Resource Manager discovery

Use two separate stacks: `terraform/stacks/discovery` for assessment and `terraform/stacks/deployment` for a selected allocation. Discovery allocates no GPU/CPU nodes. No Terraform process launches another Terraform process.

## Package and inputs

Run `make package`. Upload `work/packages/oke-llm-discovery.zip` and select working directory `terraform/stacks/discovery`. The deployment ZIP uses `terraform/stacks/deployment`.

Discovery takes a public Hugging Face URL or `owner/model`, revision, context length and concurrency. The form deliberately uses a text field: RMS does not provide a general dependent namespace/model selector for arbitrary static catalogs. The full alphabetical recipe catalog remains in `catalogs/models.json` as evidence/reference; it is not a 517-choice form control. `model_choice` is hidden legacy compatibility input, and an explicit `model` always takes priority.

The bootstrap region selector defaults to `${session.region}`. It is only the initial connection region, not a restriction on the scan. `regions` and `shape_names` are optional list controls with hidden typed items and the serialized default `"[]"`. Empty or null scope inputs mean all READY subscriptions/all visible GPU shapes. Region-scope items use a region selector; shape-scope items accept exact names such as `BM.GPU.H100.8`.

RMS Terraform receives collection overrides as expressions. An empty string (`""`) is not an empty collection. A confirmed failed job had `regions=""` and `shape_names=""`, causing `Missing expression` before defaults could apply; bootstrap `region` was already set. Remove old blank overrides or replace each with the literal string `"[]"` in the RMS variable map. Replacing a ZIP alone may preserve these old overrides.

## Dynamic SDK lookup

Hugging Face model profiling remains HTTP-provider/HCL based. Regional OCI discovery uses `hashicorp/external` with a compiled Go OCI SDK executable. The lookup enumerates READY subscriptions, instantiates regional clients dynamically, lists paginated shapes/limits, queries supported compartment headroom and requests AD capacity reports. `regions.tf` and its fixed provider aliases are removed. Native regional modules remain available for examples and deployment-time allocation admission.

The Go lookup honors `TF_VAR_auth` / `OCI_AUTH` for APIKey, InstancePrincipal and ResourcePrincipal authentication. RMS supplies InstancePrincipal in the tested execution environment; resource-principal environment variables are also detected, and local runs use DEFAULT credentials when no authentication mode is set. There is no runtime Python, OCI CLI, Go compiler, custom-provider registry or custom-provider bucket dependency. Package builds require Go 1.26+ (or Go's automatic toolchain download); the SDK/module dependencies are pinned in `tools/oci-discovery/go.mod` and `go.sum`. The ZIP includes a static Linux AMD64 and ARM64 executables with SHA256 sidecars; the launcher verifies the platform checksum and restores executable permission if extraction removed it. Local development runs `make build-discovery-sdk` before Terraform. `make test-discovery-sdk` exercises query/contract/error/pagination logic.

Four regional scans run concurrently. API failures fail the snapshot rather than becoming capacity zero. The headroom budget remains 1000 queries per region, with shape-relevant quota names first; omitted/unsupported/disabled headroom remains unknown. Capacity uses the tenancy root and shape listings separately from target-compartment entitlement. Only known AD-matched zero limits suppress capacity calls when `only_shapes_with_limits` is enabled; unmapped quotas remain included.

Capacity diagnostic reports are now requested when the data source is read, including during Plan/refresh. `observation_id` labels the result rather than controlling resource recreation. No instances are allocated or reserved. Counts represent instances, not GPUs, and candidate alternatives may share the same supply. An SDK/API snapshot does not establish runtime compatibility or RDMA placement.

### Existing native discovery state

A stack that previously applied the alias-based discovery may retain report/bookkeeping state referring to old provider aliases. Back up that state before migration. Use a new discovery stack/state, or deliberately remove only the legacy diagnostic-report/module entries after inspection; do not apply a plan blindly or discard deployment allocation state. This project does not automatically rewrite existing state. A failed job that never created resources does not require that cleanup.

## Obtain JSON

After a completed Apply job, open **Job → Outputs** for `discovery` and `assessment`. For an exact machine-readable handoff, download the Terraform state:

```sh
mkdir -p work
oci resource-manager job get-job-tf-state \
  --job-id YOUR_APPLY_JOB_OCID --region YOUR_RMS_REGION \
  --file work/rms-discovery-state.json
jq -e '.outputs.discovery.value | select(type == "object")' \
  work/rms-discovery-state.json > work/discovery.json
```

For a successful Plan, the SDK data is already read. Download its JSON plan with `oci resource-manager job get-job-tf-plan --job-id YOUR_PLAN_JOB_OCID --region YOUR_RMS_REGION --tf-plan-format JSON --file work/discovery-plan.json`, then inspect `.planned_values.outputs.discovery.value` if fully known. Plan jobs do not publish the usual completed-Apply Outputs view.

`assessment.blocking_reasons` and `evaluated_layout_count` distinguish unsupported models/engines from rejected layouts. `capacity.reported_sufficient` only compares physical instance counts with the report's requested quantity. Candidates additionally require estimator/engine coverage, compatible hardware and TP/PP partitioning, per-rank memory fit, enough hosts and no known blocked entitlement.

Flint is supported upstream by vLLM v0.33.0, while this stack's engine/estimator coverage is still limited. A recipe/catalog entry is not a promise this deployment implementation can serve it. Live recipe/flag resolution and multimodal/audio serving validation remain separate work.

## Deploy a selected configuration

Fill `terraform/stacks/deployment/target.example.json` with an existing cluster and compatible regional images/subnets. Use `scripts/select-deployment.sh` with a candidate ID to export deployment variables. The second stack uses native OCI Terraform to create retained GPU/CPU infrastructure and DevOps resources. Apply the emitted Kubernetes RBAC manifest, then run the deploy pipeline; validation follows automatically and benchmarking runs separately. See [the complete workflow](deployment-workflow.md).

References: [Oracle RMS schema/control specification](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/terraformconfigresourcemanager_topic-schema.htm), [OCI regional APIs](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/usingapi.htm), [external data-source protocol](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external), [RMS job outputs](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/list-job-outputs.htm).
