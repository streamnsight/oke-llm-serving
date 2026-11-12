<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Proposed discovery-to-deployment bundles

Status: researched proposal, 2026-11-12. This flow is not implemented yet. The existing inline JSON exporter has not established a usable RMS create-stack flow; a byte count alone is insufficient validation. The recommended replacement is a complete deployment ZIP for each selectable configuration.

## User flow

1. The user launches the discovery stack, supplies a Hugging Face model and workload requirements, and runs Apply.
2. Discovery assesses the model and subscribed-region GPU capacity, then publishes deployment ZIPs and launch URLs. Its cloud resources are an artifact bucket, objects and PARs; it allocates no GPU/CPU nodes or deployment infrastructure.
3. Each option identifies its target region, AD, shape, host/GPU quantity, serving variant, configuration-validation status and capacity timestamp.
4. The user follows the chosen launch URL. RMS opens Create Stack in the requested region with that ZIP selected. The user selects an existing OKE cluster and reviews the stack.
5. Deployment defaults to preview mode. Creating the stack or running its initial Apply does not allocate GPU resources while `provision_resources` remains false. Allocation remains an explicit later action after review.

This is one initial entry point, followed by an independent deployment stack for the option the user chooses. Publishing options does not pre-create an RMS deployment stack for every option. Refreshing/deleting discovery artifacts must not own or release the deployment stack's GPU allocation.

Oracle explicitly supports Object Storage PAR URLs in [Deploy to Oracle Cloud links](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/deploybutton.htm). These links open a wizard; they do not immediately create a stack or allocate nodes.

## Bundle contents and variable precedence

Each ZIP has root Terraform/schema files, its required modules, `inputs/discovery.json` containing one full frozen configuration, and a manifest. The deployment root reads the data file with `jsondecode(file(...))`. No large assessment is passed through an RMS variable, so the 8192-byte input limit is outside the handoff path.

Use `terraform.tfvars.json` only for deliberately fixed small values, if needed. Normal editable defaults belong in variable definitions/schema. Oracle documents that [tfvars values take precedence over imported stack variables](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/update-stack-vars-import.htm), and [RMS supplies stack variables through the job environment](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/terraformconfigresourcemanager.htm). Do not pin `cluster_id`, `region`, compartment overrides or `provision_resources` in tfvars and accidentally shadow Console edits. The expected deployment region belongs in the frozen data/manifest and is compared with the RMS-injected actual region.

Preserve model revision, image/platform digests, recipe source identity, original/resolved arguments, optional feature settings, memory assumptions, CPU estimate, topology and capacity evidence. There is no need to trim these fields to an inline budget. Retain the full multi-option assessment once as a separate audit artifact; individual bundles need only their own option.

The inner manifest records the template revision/hash, payload hash, selection ID, expected region and scan timestamp. The final ZIP hash belongs in publication metadata/outputs, not inside the ZIP whose hash it describes.

## Editable recommendations in RMS

Generate concrete defaults in each option's `schema.yaml` for small editable settings such as TP/PP, replica/node count, context/concurrency and CPU/storage sizing. These are literal values produced while assembling the ZIP; the RMS schema cannot read our arbitrary bundled JSON at form-render time. Oracle documents [schema defaults as form prefills](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/terraformconfigresourcemanager_topic-schema.htm).

Generate matching Terraform **variable declaration defaults** from the same recommendation map, so Console and CLI use the same baseline. A small `recommendations_override.tf.json` can merge only `default` attributes into the existing declarations without duplicating their types/validation. This is a [Terraform configuration override file](https://developer.hashicorp.com/terraform/language/files/override), not a `.tfvars` value-assignment file. User-supplied environment/Console values have higher priority than variable declaration defaults. [Terraform precedence](https://developer.hashicorp.com/terraform/language/values/variables).

For example, a bundle can generate this schema entry:

```yaml
tensor_parallel_size:
  type: integer
  title: Tensor parallel GPUs
  default: 4
```

And this configuration in `recommendations_override.tf.json`:

```json
{"variable":{"tensor_parallel_size":{"default":4}}}
```

An expert editing the RMS field to 2 should produce effective TP=2. The embedded recommendation remains TP=4 for comparison/provenance. The generator must keep schema/HCL defaults consistent and avoid writing adjustable settings into any automatically loaded tfvars file. Local core-Terraform verification passed: default=4, `TF_VAR_tensor_parallel_size=2` produces 2, and the original positive-integer validation still rejects 0. This verifies Terraform precedence; generated-schema behavior still needs the planned authenticated RMS form test.

Large recipe arguments, environment definitions and complete assessment evidence stay in the bundled JSON, outside the variable-size limit. Advanced controls can supply optional overrides without putting the entire recommendation into RMS variables. Cluster and region-specific node image/subnet IDs remain blank/automatic until cluster discovery; the cluster picker and stack-compartment default stay dynamic. The RMS-injected actual `region` must remain distinct from the bundle's expected region.

The HCL resolver must honor explicit overrides before recommendation fallback. Some current fields, including shape/AD, prefer the selected record unconditionally; updating schema defaults alone would not make those values editable. Compare effective values with recommended values to detect changes rather than using `var != null`, since generated defaults themselves are non-null. Report changed fields and mark affected serving configurations as expert-modified/untested.

When TP/PP, context, concurrency, quantization or hardware changes, discard any old per-rank memory-fit result and recompute it, or require an explicit expert bound if estimation is unsupported. Recheck geometry, platform/image compatibility, quota and requested-quantity capacity before allocation. A changed region/model/shape invalidates the original recommendation; use a matching fresh assessment or an explicitly revalidated expert path. Existing allocation-retention guards remain active. An editable form must not silently ignore changes or preserve stale fit/validation claims.

## Build and publish

At release packaging time, build the generic deployment template from the same committed revision and embed it in the discovery package. Include only the deployment dependency closure; the deployment template must not contain the publisher or recursively embed another copy of itself. Preserve root-level `main.tf` and `schema.yaml` in every generated ZIP.

At discovery Apply, a module-local publisher combines the template with each frozen option using the native HashiCorp archive provider, then uploads through native OCI Object Storage resources and creates object-scoped `ObjectRead` PARs. No nested Terraform execution or Python/Go helper is required for this publication flow. The current runtime source template is text; packaging tests must detect unsupported binary assets rather than corrupting them through `file()`.

Use the archive **resource** for Apply-time generation. The [archive data source](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) creates a file during Plan and explicitly requires preserving it until Apply; that is an unsuitable assumption for separate RMS workers. The [resource](https://raw.githubusercontent.com/hashicorp/terraform-provider-archive/main/docs/resources/file.md) supports composing multiple source files. Test saved-Plan/Apply jobs with an empty generated-files directory and stable inputs, including repeated jobs and refreshes.

Keep the artifact bucket private, centrally in the discovery/artifact region. ZIP object names must visibly identify the normalized Hugging Face model ID, *deployment* region, shape and publication version. Include a full UTC timestamp in the filename and a unique publication/run ID in the path; a date alone can collide during multiple runs in one day. For example:

```text
models/Qwen--Qwen3.8-27B/us-ashburn-1/BM.GPU.A10.4/20261112T213000Z-c83f94a1/<selection-id>/deployment-20261112T213000Z.zip
```

Normalize the model ID safely for the path and retain its exact ID/revision in the manifest. Generate the publication timestamp/run ID once per refresh and reuse them for every object, manifest and URL in that publication. Keep values stable through a saved Plan/Apply pair; a new discovery publication gets a new path even if recommendations are unchanged. Record payload/template hashes as integrity evidence, not as the only version identifier. Avoid evaluating independent timestamps in each resource or using date-only names.

A new publication updates discovery's output links. A `/stacks/create` URL opens a new-stack wizard; it does not update an existing deployment stack. Updating an existing deployment should explicitly replace that stack's configuration with the new ZIP and run Plan against its existing state. A discovery refresh must not silently update live infrastructure or create replacement GPU allocations.

The PAR hostname identifies the bucket region, which need not be the GPU region. Use object-level read-only PARs with a configurable short lifetime (recommended initial default: 24 hours), preserve immutable snapshot paths while published, and document rotation/cleanup behavior. The URL grants read access to the ZIP; credentials must not be embedded. Publishing needs bucket/object/PAR permissions in the artifact compartment. [Oracle PAR scope and expiry documentation](https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/usingpreauthenticatedrequests.htm).

Archive/upload cost scales with option count times template size: O(N × S + total option payload size). The current generic deployment ZIP is about 201 KiB, so 13 choices require roughly 2.6 MiB plus per-choice data. Reduce duplicated template dependencies and measure state size/runtime as the option count grows; do not duplicate the entire all-region report in every bundle.

## Launch URLs and outputs

Construct the link with the full PAR URL percent-encoded as a query value:

```text
https://cloud.oracle.com/resourcemanager/stacks/create?region=us-ashburn-1&zipUrl=<URL_ENCODED_PAR_ZIP_URL>
```

Validate actual region routing in an authenticated Console, including redirects after sign-in. Keep the Terraform wrong-region guard even when the URL includes a region. The URL chooses the UI region; the frozen region/AD/shape remain deployment requirements. Existing cluster selection must resolve in that region and its VCN/network checks remain active.

Emit `deployment_options` containing each option's label, target region/AD, shape/quantity, model/engine variant, scan time, expiry, ZIP hash, download URL and launch URL. A known scalar recommended launch URL can be rendered as a native schema `link`/primary button. Oracle's [schema documentation](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/terraformconfigresourcemanager_topic-schema.htm) says map outputs render as JSON; do not assume nested URLs become individual buttons. Validate the all-options presentation in RMS. An additional choice index can be considered if needed, with browser rendering verified before relying on it.

Only capacity/headroom-confirmed choices enter publication. Preserve the distinction between available-at-scan capacity and untested serving configurations. Deployment rechecks allocation-time entitlement/capacity; PAR validity is not a reservation or proof capacity remains available.

## Implementation phases and verification

1. [ ] Add bundled-data loading, generated schema/HCL defaults and a manifest to deployment; remove large JSON inputs from the normal generated schema. Verify a payload well over 8192 bytes loads without a large RMS variable, Console edits reach the effective plan, and overrides invalidate stale sizing/validation evidence. No adjustable value may be shadowed by tfvars.
2. [ ] Build and embed the deployment template without recursion. Verify every generated archive has root Terraform/schema files, the exact frozen selection and all referenced runtime assets; initialize/validate extracted bundles.
3. [ ] Add native Apply-time archives, private bucket/object publication, object-read PARs and encoded region-specific links. Include model/region/shape and a timestamp/run ID in object names. Verify reruns publish distinct names, same-publication filenames stay consistent, wrong-region rejection, expiry/rotation, required IAM and saved-Plan/Apply worker separation. Discovery creates artifact resources only.
4. [ ] Test the authenticated launch wizard and the all-options UI, preserving the dynamic cluster picker and preview default. Confirm RMS imports/stores the ZIP so later jobs do not need a still-valid download PAR; test a subsequent preview job after revoking the PAR.
5. [ ] Replace the inline-budget workflow/docs with generated bundle links and remove its obsolete paths after validation. Commit/integrate following the repository workflow. No GPU creation, resizing or deletion is part of these tests.
