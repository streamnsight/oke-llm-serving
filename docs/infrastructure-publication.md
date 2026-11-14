<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Discovery publishes infrastructure launch bundles

Discovery is the repository root. `make package` builds one entry ZIP containing reusable modules and downstream templates. Discovery Apply now renders/publishes **infrastructure** ZIPs for confirmed choices. The older combined deployment template is embedded for development, but is not published as a model-only stack. Model deployment/undeploy remains pending.

`publish_infrastructure_bundles` defaults to true; set false for assessment-only runs. Artifact storage defaults to the RMS stack compartment, with an optional override. Local runs fall back to the assessment compartment/tenancy. Native OCI authentication follows the execution environment and normal local DEFAULT profile. The principal needs namespace access and bucket/object/PAR permissions in the artifact compartment. Discovery creates no GPU hosts, node pools, cluster components or DevOps pipelines.

## Run and choose

Run discovery Plan and Apply in RMS. The primary button opens the separate HTML comparison page; RMS also displays the complete consolidated `discovery` JSON. `deployment_option_count` shows the choices. Select any region/AD/shape through `discovery.options[ID].links.launch_url`; `recommended_launch_url` is a secondary convenience link. Entries include host count, capacity observation time, configuration status, ZIP SHA256, expiry and download URL. Zero/unknown-capacity choices remain diagnostics. A launch link does not reserve hosts or provision infrastructure.

```sh
terraform init
terraform plan -var-file=/path/to/request.tfvars.json -out=work/discovery.tfplan
terraform apply work/discovery.tfplan
terraform output -json discovery > work/discovery.json
terraform output -raw recommended_launch_url
```

The launch URL selects the GPU region and an object-read PAR. The bucket can be in another region. The publisher normalizes newer commercial `namespace.objectstorage.REGION.oci.customer-oci.com` URLs to the classic `objectstorage.REGION.oraclecloud.com` endpoint documented for RMS quick-create links, then URL-encodes the complete PAR. Storage region and PAR path remain unchanged; other endpoint formats pass through. Open a chosen link, select an existing cluster and review preview. Apply allocates GPU hosts by default. Set discovery’s temporary `skip_gpu_allocation=true` debug switch to prefill generated ZIPs to skip GPU allocation while still creating the DevOps foundation. The child switch remains editable in RMS. The generated stack rejects a region different from its bundled specification.

For an existing link returning GetPackage InvalidParameter(400), changing only that hostname inside its `zipUrl` can avoid the endpoint compatibility issue without re-uploading the ZIP or replacing its PAR. [Oracle's troubleshooting](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Troubleshoot/deploy-button.htm) first requires a valid, anonymously accessible ZIP; [its quick-create documentation](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/create-quick-create-links-stacks.htm) shows the classic endpoint format. A successful download alone does not establish successful RMS import; verify the Console wizard separately.

The Console ZIP-import flow adds a `ZipOrigin` free-form tag containing the package URL. Earlier descriptive object paths produced 285–288-character values, exceeding [OCI's 256-character tag-value limit](https://docs.oracle.com/en-us/iaas/Content/Tagging/Concepts/taggingoverview.htm). Clearing a wizard was only a workaround: every new quick-create launch added it again. The publisher now keeps the descriptive archive and uploads an identical short-path launch copy; its object-scoped PAR supplies `download_url`/`launch_url`. The final package URL must fit 256 characters or publication fails rather than emitting a link known to fail stack creation. The Console can still add the tag; the ZIP and Terraform do not declare it, and the documented quick-create parameters provide no suppression switch.

Existing cloud objects and URLs are unchanged until discovery is updated with the new entry ZIP and Apply republishes the choices. For an already-open wizard using an old long URL, in **Stack information → Tags**, clear both **Tag key** and **Tag value**; removing the only row can be disabled. Check Review has no Tags section before Create. Changing to a defined tag does not change the value limit. Directly uploading a downloaded ZIP avoids the quick-create origin URL. Bundle provenance remains in `bundle-manifest.json`.

## Rendering and editability

The native archive resource generates ZIPs at Apply. The publisher copies the infrastructure root and its grouped runtime/module closure and the next model template, without the parent discovery publisher, provider caches, tests, state or private tfvars. Unsupported binary assets fail rather than being corrupted. Each ZIP has root main.tf/schema.yaml/modules plus:

- `recommendations_override.tf.json`: Terraform declaration defaults matching the generated schema. Console/environment edits take precedence.
- `inputs/infrastructure-spec.json`: the chosen option, model identity/revision/workload assumptions and template provenance. Files can exceed 8192 bytes without using an RMS input variable.
- `bundle-manifest.json`: option ID, expected region, publication/run identity and template/payload hashes. The final ZIP hash is returned in publication outputs.

The cluster picker/stack compartment remain dynamic. The actual RMS region is not replaced by a generated default. Expert edits to recommended hardware/storage appear in preview and invalidate the original sizing claim. Allocation rechecks live quantity-specific capacity and entitlement. Disk recommendations reserve two checkpoint copies per packed serving pod plus 100 GiB, with a 200 GiB minimum; runtime cache sizing remains a model concern.

## Lifetime and ownership

Paths retain fixed model/region/shape folders, with timestamp/run/option identity only in the filename:

```text
models/org--model/us-phoenix-1/BM.GPU.A10.4/
  infrastructure-20261113T010000Z-<run-id>-<option-id>.zip
```

One Terraform publication record supplies Apply time and run identity consistently to all filenames, manifests and expiry values. Every Apply publishes fresh choices. PARs are object-scoped ObjectRead, default to 24 hours and allow 1–168 hours. Refresh/destroy can revoke older PARs and replace/remove older managed objects. This version does not provide append-only artifact history; retain a downloaded ZIP when needed. Discovery never owns the independent infrastructure state's GPU hosts. Create-stack links open new-stack wizards, not updates to existing stacks.

The same bucket also holds `rms/<run-id>-<option-hash>.zip` launch copies. These filenames have a fixed length independent of model name and region. Both objects use the same generated ZIP and checksum; only the short launch object receives the PAR. Publication outputs identify the descriptive `object_name` and the short `launch_object_name` separately. The additional object preserves browsable model/region/shape folders without placing their length in the Console-created tag.

PARs grant access to their ZIPs, so restrict access to discovery outputs/state. The bucket stays private and bundles contain no credentials. Expired links require another Apply. Capacity remains a scan-time observation that can change before allocation.

## Verification boundary

Tests use the real archive provider and actual ZIPs, with OCI storage/PAR operations mocked. Extracted child tests cover defaults, a selected file larger than the RMS input limit, expert overrides, region rejection and GPU-skipping debug mode that still creates platform resources. An archive-only saved-Plan fixture runs Apply in a fresh directory without Plan-generated ZIPs. CI repeats these development checks. No Terraform configuration invokes nested Terraform.

The user's live publication, PAR download and corrected Frankfurt import through Configure variables/Review were observed. No stack creation or GPU allocation was performed by the agent. Infrastructure Apply, bootstrap IAM/connectivity and the complete workflow across RMS workers still need validation. See [the broader bundle design](generated-deployment-bundles.md) for model-only work and remaining integration steps.
