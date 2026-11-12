<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Resource Manager discovery

Use two separate stacks: `terraform/stacks/discovery` for assessment and `terraform/stacks/deployment` for a selected allocation. Discovery allocates no GPU/CPU nodes. No Terraform process launches another Terraform process.

## Package and inputs

Run `make package`. Upload `work/packages/oke-llm-discovery.zip` and select working directory `terraform/stacks/discovery`. The deployment ZIP uses `terraform/stacks/deployment`.

Discovery takes a public Hugging Face URL or `owner/model`, revision, context length and concurrency. The form deliberately uses a text field: RMS does not provide a general dependent namespace/model selector for arbitrary static catalogs. The full alphabetical recipe catalog remains in `catalogs/models.json` as evidence/reference; it is not a 517-choice form control. `model_choice` is hidden legacy compatibility input, and an explicit `model` always takes priority.

Discovery automatically identifies the tenancy home region from `is_home_region` subscription metadata and uses that endpoint for the subscription lookup. There is no visible bootstrap-region field. RMS injects its current session region as hidden initial connection context; local runs may omit `region` and use their CLI profile/defaults to make the first lookup. The session region is not assumed to be the home region. `regions` and `shape_names` are optional list controls with hidden typed items and the serialized default `"[]"`. Empty or null scope inputs mean all READY subscriptions/all visible GPU shapes. Region-scope items use a region selector; shape-scope items accept exact names such as `BM.GPU.H100.8`.

RMS Terraform receives collection overrides as expressions. An empty string (`""`) is not an empty collection. A confirmed failed job had `regions=""` and `shape_names=""`, causing `Missing expression` before defaults could apply; the internal initial connection `region` was already set. Remove old blank overrides or replace each with the literal string `"[]"` in the RMS variable map. Replacing a ZIP alone may preserve these old overrides.

## Dynamic CLI lookup

Hugging Face profiling remains HTTP-provider/HCL based. Regional discovery uses `hashicorp/external` to run `scripts/discover-oci.sh` with Bash, OCI CLI and jq. It dynamically enumerates READY subscriptions, queries regional inventory/limits/headroom and requests AD capacity reports. No regional provider aliases, Go binaries, custom Python scripts or nested Terraform process are used. Native regional modules remain available for deployment allocation/admission and examples.

The helper honors `TF_VAR_auth` / `OCI_AUTH` for APIKey, InstancePrincipal and ResourcePrincipal. Local runs preserve CLI config/profile/environment defaults. RMS supplies InstancePrincipal plus delegated caller settings: `use_obo_token`, `obo_token_path` and `obo_token`, with `TF_VAR_`, `OCI_` or bare names. These map to CLI `instance_obo_user` auth. The helper creates a private temporary CLI config referring to the token file; if only token content is supplied, it creates a private temporary token file as well. Temporary files are deleted on exit. No token enters Terraform outputs or argv. No broader IAM permissions or local API keys are required.

The actual RMS runtime probe found OCI CLI and Python OCI SDK 2.189.0 on Python 3.9.25. This is an observation of the tested host, not a guarantee of every future RMS image. Missing CLI/jq fails with a clear dependency message. The stack does not install packages at runtime. Packaging needs Bash, jq and zip; catalog refresh additionally uses Node only as a build-time YAML parser.

Four regional scans run concurrently in bounded batches. Separate CLI processes add startup/authentication overhead compared with a long-lived SDK client. API failures fail the snapshot rather than becoming capacity zero. The headroom budget remains 1000 queries per region, with shape-relevant quota names first; omitted/unsupported/disabled headroom remains unknown. Capacity uses the tenancy root and shape listings separately from target-compartment entitlement. Only known AD-matched zero limits suppress capacity calls when `only_shapes_with_limits` is enabled; unmapped quotas remain included.

Capacity diagnostic reports are now requested when the data source is read, including during Plan/refresh. `observation_id` labels the result rather than controlling resource recreation. No instances are allocated or reserved. Counts represent instances, not GPUs, and candidate alternatives may share the same supply. A CLI/API snapshot does not establish runtime compatibility or RDMA placement.

### Existing native discovery state

A stack that previously applied the alias-based discovery may retain report/bookkeeping state referring to old provider aliases. Back up that state before migration. Use a new discovery stack/state, or deliberately remove only the legacy diagnostic-report/module entries after inspection; do not apply a plan blindly or discard deployment allocation state. This project does not automatically rewrite existing state. A failed job that never created resources does not require that cleanup.

## Obtain JSON

After a completed Apply job, open **Job → Outputs** for `deployment_inputs` (the handoff) and `discovery` / `assessment` (full reports). For an exact machine-readable handoff, download the Terraform state:

```sh
mkdir -p work
oci resource-manager job get-job-tf-state \
  --job-id YOUR_APPLY_JOB_OCID --region YOUR_RMS_REGION \
  --file work/rms-discovery-state.json
jq -e '.outputs.deployment_inputs.value | select(type == "object")' \
  work/rms-discovery-state.json > work/deployment-inputs.tfvars.json
```

For a successful Plan, the CLI data is already read. Download its JSON plan with `oci resource-manager job get-job-tf-plan --job-id YOUR_PLAN_JOB_OCID --region YOUR_RMS_REGION --tf-plan-format JSON --file work/discovery-plan.json`, then extract `.planned_values.outputs.deployment_inputs.value` if fully known. Plan jobs do not publish the usual completed-Apply Outputs view.

`assessment.blocking_reasons` and `evaluated_layout_count` distinguish unsupported models/engines from rejected layouts. `capacity.reported_sufficient` only compares physical instance counts with the report's requested quantity. Candidates additionally require estimator/engine coverage, compatible hardware and TP/PP partitioning, per-rank memory fit, enough hosts and no known blocked entitlement.

Discovery assesses recipes, stable/nightly candidates, published image platforms and feature definitions automatically. Image/channel/version/platform and feature overrides are inputs of the deployment stack only. `serving_configuration` freezes the result for deployment. `assessment.sizing_options` contains undetermined GPU alternatives requiring explicit expert settings. See [runtime serving resolution](runtime-serving-resolution.md). Flint resolves to supporting stable/nightly images, while per-rank estimation and GPU runtime validation remain limited. See [the Flint gap assessment](flint-assessment.md) for recipe evidence and required changes. A recipe/catalog entry is not a promise this deployment implementation can serve it. Multimodal/audio serving validation and GGUF resident-memory profiling remain separate work.

## Deploy a selected configuration

Fill `terraform/stacks/deployment/target.example.json` with an existing cluster and compatible regional images/subnets. Pass the one deployment_inputs JSON unchanged, choose `selection_id` and target infrastructure in deployment. The selection shell script remains a legacy helper and is not needed for this flow. The second stack uses native OCI Terraform to create retained GPU/CPU infrastructure and DevOps resources. Apply the emitted Kubernetes RBAC manifest, then run the deploy pipeline; validation follows automatically and benchmarking runs separately. See [the complete workflow](deployment-workflow.md).

References: [Oracle RMS schema/control specification](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/terraformconfigresourcemanager_topic-schema.htm), [OCI regional APIs](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/usingapi.htm), [external data-source protocol](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external), [RMS job outputs](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/list-job-outputs.htm).
