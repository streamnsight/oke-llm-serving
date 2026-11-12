<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Resource Manager discovery

Use two separate stacks: `terraform/stacks/discovery` for assessment and `terraform/stacks/deployment` for a selected allocation. Discovery allocates no GPU/CPU nodes. No Terraform process launches another Terraform process.

## Package and inputs

Run `make package`. Upload `work/packages/oke-llm-discovery.zip` or `oke-llm-deployment.zip` and use the ZIP root (`.`) as working directory. There is no enclosing stack/repository folder:

```text
main.tf
variables.tf
schema.yaml
.terraform.lock.hcl
modules/
  oci-discovery/scripts/
  accelerator-inventory/data/gpus.json
  devops-serving/scripts/
  devops-serving/data/components.json
```

Packaging relocates local module sources to `./modules/...` and updates module-relative catalog/DevOps paths in the staged copy. The repository development layout stays unchanged. For an existing RMS stack, replace its old `terraform/stacks/...` working-directory setting with `.` when uploading the new ZIP. If linking directly to the Git repository instead, continue using `terraform/stacks/discovery` or `terraform/stacks/deployment`.

Run `make check-packages` to build, extract, initialize and validate both delivered archives. This check runs without OCI credentials or capacity queries. Only committed source is packaged; state, local inputs, caches, private work files and development tests are excluded.

The [Package RMS stacks workflow](../.github/workflows/package-stacks.yaml) runs on pushes to `main` (including merges), or manually through Actions. It checks both packages before publishing `oke-llm-discovery.zip` and `oke-llm-deployment.zip` as separate downloadable run artifacts. Download the selected ZIP from **Actions → Package RMS stacks → successful run → Artifacts**, then upload that file directly to RMS. The upload uses [single-file artifact mode](https://github.com/actions/upload-artifact#upload-an-individual-file-unzipped), so there is no additional archive wrapper. Artifact expiry follows the repository's Actions retention setting. This is run-artifact publication, not a GitHub Release.

Discovery takes a public Hugging Face URL or `owner/model`, revision, context length and concurrency. The form deliberately uses a text field: RMS does not provide a general dependent namespace/model selector for arbitrary static catalogs. Model and variant metadata are resolved live; no model dropdown, static model index or catalog refresh is used.

Discovery automatically identifies the tenancy home region from `is_home_region` subscription metadata and uses that endpoint for the subscription lookup. There is no visible bootstrap-region field. The CLI infers the first endpoint from its authenticated principal or local profile, then discovers the actual home region. The hidden legacy `region` hint defaults empty. Literal old `${session.region}` values are ignored instead of becoming endpoint hostnames. `regions` and `shape_names` are optional list controls with hidden typed items and the serialized default `"[]"`. Empty or null scope inputs mean all READY subscriptions/all visible GPU shapes. Blank/whitespace-only entries (including RMS `shape_names=[""]`) are removed rather than filtering out every shape. Region-scope items use a region selector; shape-scope items accept exact names such as `BM.GPU.H100.8`.

RMS Terraform receives collection overrides as expressions. An empty string (`""`) is not an empty collection. A confirmed failed job had `regions=""` and `shape_names=""`, causing `Missing expression` before defaults could apply; the internal initial connection `region` was already set. Remove old blank overrides or replace each with the literal string `"[]"` in the RMS variable map. Replacing a ZIP alone may preserve these old overrides.

## Dynamic CLI lookup

Hugging Face profiling remains HTTP-provider/HCL based. Regional discovery uses `hashicorp/external` to run `terraform/modules/oci-discovery/scripts/discover-oci.sh` with Bash, OCI CLI and jq. It dynamically enumerates READY subscriptions, queries regional inventory/limits/headroom and requests AD capacity reports. No regional provider aliases, Go binaries, custom Python scripts or nested Terraform process are used. Native regional modules remain available for deployment allocation/admission and examples.

The helper honors `TF_VAR_auth` / `OCI_AUTH` for APIKey, InstancePrincipal and ResourcePrincipal. Local runs preserve CLI config/profile/environment defaults. RMS supplies InstancePrincipal plus delegated caller settings: `use_obo_token`, `obo_token_path` and `obo_token`, with `TF_VAR_`, `OCI_` or bare names. These map to CLI `instance_obo_user` auth. The helper creates a private temporary CLI config referring to the token file; if only token content is supplied, it creates a private temporary token file as well. Temporary files are deleted on exit. No token enters Terraform outputs or argv. No broader IAM permissions or local API keys are required.

The actual RMS runtime probe found OCI CLI and Python OCI SDK 2.189.0 on Python 3.9.25. This is an observation of the tested host, not a guarantee of every future RMS image. Missing CLI/jq fails with a clear dependency message. The stack does not install packages at runtime. Packaging needs Bash, jq and zip; catalog refresh additionally uses Node only as a build-time YAML parser.

Four regional scans run concurrently in bounded batches. Separate CLI processes add startup/authentication overhead compared with a long-lived SDK client. API failures fail the snapshot rather than becoming capacity zero. The headroom budget remains 1000 queries per region, with shape-relevant quota names first; omitted/unsupported/disabled headroom remains unknown. Capacity uses the tenancy root and shape listings separately from target-compartment entitlement. Only known AD-matched zero limits suppress capacity calls when `only_shapes_with_limits` is enabled; unmapped quotas remain included.

Capacity diagnostic reports are now requested when the data source is read, including during Plan/refresh. `observation_id` labels the result rather than controlling resource recreation. No instances are allocated or reserved. Counts represent instances, not GPUs, and candidate alternatives may share the same supply. A CLI/API snapshot does not establish runtime compatibility or RDMA placement.

### Existing native discovery state

## Obtain JSON

After a completed Apply job, open **Job → Outputs** for `deployment_handoffs` (compact per-selection inputs) and `discovery` / `assessment` / `deployment_inputs` (full reports). For exact machine-readable outputs, download the Terraform state:

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

RMS limits each variable value to 8192 bytes. Do not paste the full `deployment_inputs` report into a variable. Copy the selected `deployment_handoffs[ID].inline_json`; it contains one frozen choice and is measured against an 8000-byte budget. If it is null, use the emitted `object_json` through authenticated Object Storage instead. [The preview/handoff guide](deployment-preview.md) includes exact export commands.

Create the deployment stack in the selected GPU region, paste that compact JSON and choose an existing cluster using the dynamic picker. The compartment defaults to the stack compartment. Images, known worker/pod subnets and NSGs are resolved from OCI; normal users need not supply their OCIDs. The default preview creates no OCI resources. Review its output before opting into allocation and DevOps provisioning. See [the complete workflow](deployment-workflow.md).

References: [Oracle RMS schema/control specification](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/terraformconfigresourcemanager_topic-schema.htm), [OCI regional APIs](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/usingapi.htm), [external data-source protocol](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external), [RMS job outputs](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/list-job-outputs.htm).

## Selectable capacity

`assessment.suggestions`, `candidates` and `sizing_options` include only options with sufficient physical host capacity and quantity-confirmed GPU headroom at scan time. Unknown is not eligible. Excluded observations remain under `availability_diagnostics` and `sizing_diagnostics`, with reasons. Quota units follow allocation admission: explicit GPU-unit evidence is required and a whole eight-GPU host needs eight GPUs of entitlement even for TP2/TP4. Missing, unsupported or disabled headroom queries therefore exclude an option rather than suggesting a speculative allocation. Run discovery again for a current snapshot; installing a new ZIP does not refresh existing RMS state outputs.
