<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Proposed discovery-to-deployment bundles

Status: researched proposal, 2026-11-12. This flow is not implemented yet. The existing inline JSON exporter has not established a usable RMS create-stack flow; a byte count alone is insufficient validation. The recommended replacement is generated infrastructure/model ZIPs with separate lifecycles. See [platform and model ownership](platform-model-lifecycles.md) for the three-stack design.

## User flow

1. The user launches the discovery stack, supplies a Hugging Face model and workload requirements, and runs Apply.
2. Discovery assesses the model and subscribed-region GPU capacity, or a selected existing allocation, then publishes matching infrastructure/model ZIPs and launch URLs. Its cloud resources are an artifact bucket, objects and PARs; it allocates no GPU/CPU nodes or deployment infrastructure.
3. Each option identifies its target region, AD, shape, host/GPU quantity, serving variant, configuration-validation status and capacity timestamp.
4. For new capacity, the user follows the infrastructure URL, selects an existing OKE cluster and reviews derived VCN/image/subnet/NSG details. Infrastructure owns the retained pools, shared platform components and shared DevOps project.
5. After infrastructure provisioning/bootstrap, a model launch URL can be bound to the actual platform/pool/project. The model stack owns only its model workloads and per-model pipelines; it reuses the existing allocation. A compatible existing platform allows a direct model-deployment path.
6. Both deployment types default to preview mode. Creating a stack does not allocate GPU resources while provisioning remains disabled. Hardware allocation remains an explicit infrastructure action; model deployment has no node-pool lifecycle ownership.

This is one initial entry point, followed by a reusable infrastructure stack and independently replaceable model stacks. Publishing options does not pre-create an RMS stack for every option. Refreshing/deleting discovery artifacts or retiring a model must not own or release the infrastructure stack's GPU allocation.

Oracle explicitly supports Object Storage PAR URLs in [Deploy to Oracle Cloud links](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/deploybutton.htm). These links open a wizard; they do not immediately create a stack or allocate nodes.

## Bundle contents and variable precedence

Each ZIP has root Terraform/schema files, its required modules, a selected `inputs/infrastructure-spec.json` or `inputs/model-spec.json`, and a manifest. A model bundle also contains or references its platform binding. The full discovery report is not required in either bundle; it is kept separately for audit. The relevant root reads its selected specification with `jsondecode(file(...))`. No large assessment is passed through an RMS variable, so the 8192-byte input limit is outside the handoff path.

Use `terraform.tfvars.json` only for deliberately fixed small values, if needed. Normal editable defaults belong in variable definitions/schema. Oracle documents that [tfvars values take precedence over imported stack variables](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/update-stack-vars-import.htm), and [RMS supplies stack variables through the job environment](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/terraformconfigresourcemanager.htm). Do not pin `cluster_id`, `region`, compartment overrides or `provision_resources` in tfvars and accidentally shadow Console edits. The expected deployment region belongs in the frozen data/manifest and is compared with the RMS-injected actual region.

Preserve each layer's relevant fields: infrastructure requirements and allocation/platform identity in the infrastructure bundle; model revision, serving image digests, recipe source, original/resolved arguments, optional features, memory assumptions and topology in the model bundle. There is no need to trim these fields to an inline budget. Retain the full multi-option assessment once as a separate audit artifact.

The inner manifest records the template revision/hash, payload hash, selection ID, expected region and scan timestamp. The final ZIP hash belongs in publication metadata/outputs, not inside the ZIP whose hash it describes.

## Editable recommendations in RMS

Create the actual `schema.yaml` in each generated ZIP from a committed base schema/template and the selected recommendation map. Populate small editable defaults for that layer: for example pool/CPU/storage sizing in infrastructure, TP/PP/replicas/context/concurrency in model deployment. These are literal values produced while assembling the ZIP; the RMS schema cannot read arbitrary bundled JSON at form-render time. Oracle documents [schema defaults as form prefills](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/terraformconfigresourcemanager_topic-schema.htm).

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

Large recipe arguments, environment definitions and relevant source evidence stay in the selected model specification, outside the variable-size limit. Advanced controls can supply optional overrides without putting the entire recommendation into RMS variables. The infrastructure cluster picker and stack-compartment default stay dynamic; images/VCN/subnets/NSGs are derived once the cluster is known, with input only for ambiguity/overrides. A model link bound to a prepared platform should not ask for those details again. The RMS-injected actual `region` must remain distinct from the bundle's expected region.

The HCL resolver must honor explicit overrides before recommendation fallback. Some current fields, including shape/AD, prefer the selected record unconditionally; updating schema defaults alone would not make those values editable. Compare effective values with recommended values to detect changes rather than using `var != null`, since generated defaults themselves are non-null. Report changed fields and mark affected serving configurations as expert-modified/untested.

When TP/PP, context, concurrency, quantization or hardware changes, discard any old per-rank memory-fit result and recompute it, or require an explicit expert bound if estimation is unsupported. Recheck geometry, platform/image compatibility, quota and requested-quantity capacity before allocation. A changed region/model/shape invalidates the original recommendation; use a matching fresh assessment or an explicitly revalidated expert path. Existing allocation-retention guards remain active. An editable form must not silently ignore changes or preserve stale fit/validation claims.

## Build and publish

At release packaging time, build infrastructure and model templates from the same committed revision and embed the required templates in discovery. Infrastructure may also carry the model template to emit links bound to its resolved IDs. Keep the embedding graph finite (discovery to infrastructure to model) and include only each root's dependency closure. A model bundle must not embed its parent publisher/templates or contain allocation-management resources. Preserve root-level `main.tf` and `schema.yaml` in every ZIP.

At discovery Apply, a module-local publisher combines the template with each frozen option using the native HashiCorp archive provider, then uploads through native OCI Object Storage resources and creates object-scoped `ObjectRead` PARs. No nested Terraform execution or Python/Go helper is required for this publication flow. The current runtime source template is text; packaging tests must detect unsupported binary assets rather than corrupting them through `file()`.

Use the archive **resource** for Apply-time generation. The [archive data source](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) creates a file during Plan and explicitly requires preserving it until Apply; that is an unsuitable assumption for separate RMS workers. The [resource](https://raw.githubusercontent.com/hashicorp/terraform-provider-archive/main/docs/resources/file.md) supports composing multiple source files. Test saved-Plan/Apply jobs with an empty generated-files directory and stable inputs, including repeated jobs and refreshes.

Keep the artifact bucket private, centrally in the discovery/artifact region. Use one stable folder per normalized model ID, deployment region and shape. Put the bundle kind, full UTC timestamp, run ID and option ID in the ZIP filename. Run IDs must not create another folder level. For example, repeated publications appear together in the same folder:

```text
models/Qwen--Qwen3.8-27B/us-ashburn-1/BM.GPU.A10.4/
  infrastructure-20261112T213000Z-c83f94a1-<option-id>.zip
  model-20261112T213000Z-c83f94a1-<option-id>.zip
  infrastructure-20261112T221000Z-e217a8b4-<option-id>.zip
  model-20261112T221000Z-e217a8b4-<option-id>.zip
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

New-allocation choices require confirmed capacity/headroom. Reuse choices are assessed against an already retained pool and its available resources, independently of spare regional capacity. Preserve the distinction between available-at-scan capacity and untested serving configurations. Infrastructure rechecks entitlement/capacity when adding hosts; PAR validity is not a reservation or proof capacity remains available.

## Implementation phases and verification

1. [ ] Establish the infrastructure/model ownership and platform contract described in [the lifecycle plan](platform-model-lifecycles.md). Add selected-spec loading, generated schema/HCL defaults and manifests to both roots. Verify a payload over 8192 bytes loads without a large variable and Console edits reach the effective plan without stale sizing evidence.
2. [ ] Build/embed both templates without recursion. Verify root Terraform/schema files, exact selected specifications and referenced assets. A model plan/retirement must not manage infrastructure resources or the shared project.
3. [ ] Add native Apply-time archives, private bucket/object publication, object-read PARs and encoded region-specific links. Keep folders fixed at model/region/shape; put timestamp/run/option IDs only in filenames. Verify distinct reruns, filename consistency, region guards, expiry/rotation, IAM and separate Plan/Apply workers.
4. [ ] Test authenticated new-infrastructure and existing-platform model flows, generated defaults, dynamic cluster/network discovery and preview defaults. Confirm RMS stores imported ZIPs so later jobs survive download PAR revocation. Verify new model deployment can reuse a suitable retained pool with zero spare regional capacity.
5. [ ] Replace the inline-budget workflow/docs with generated bundle links and remove its obsolete paths after validation. Commit/integrate following the repository workflow. No GPU creation, resizing or deletion is part of these tests.
