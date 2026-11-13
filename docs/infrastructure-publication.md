<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Discovery publishes infrastructure launch bundles

Discovery is the repository root. `make package` builds one entry ZIP containing reusable modules and downstream templates. Discovery Apply now renders/publishes **infrastructure** ZIPs for confirmed choices. The older combined deployment template is embedded for development, but is not published as a model-only stack. Model deployment/undeploy remains pending.

`publish_infrastructure_bundles` defaults to true; set false for assessment-only runs. Artifact storage defaults to the RMS stack compartment, with an optional override. Local runs fall back to the assessment compartment/tenancy. Native OCI authentication follows the execution environment and normal local DEFAULT profile. The principal needs namespace access and bucket/object/PAR permissions in the artifact compartment. Discovery creates no GPU hosts, node pools, cluster components or DevOps pipelines.

## Run and choose

Run discovery Plan and Apply in RMS. After Apply, Application Information offers a recommended infrastructure link and a `deployment_options` JSON map of published choices. Entries include region/AD, shape/host count, capacity observation time, configuration status, ZIP SHA256, expiry, download URL and create-stack URL. Zero/unknown-capacity choices remain diagnostics. A launch link does not reserve hosts or provision infrastructure.

```sh
terraform init
terraform plan -var-file=/path/to/request.tfvars.json -out=work/discovery.tfplan
terraform apply work/discovery.tfplan
terraform output -json deployment_options > work/deployment-options.json
terraform output -raw recommended_launch_url
```

The launch URL selects the GPU region and an object-read PAR. The bucket can be in another region. Its native full PAR URL is encoded as the Console query value. Open a chosen link, select an existing cluster and review preview. Only explicitly enabling `provision_resources` allocates hosts. The generated stack rejects a region different from its bundled specification.

## Rendering and editability

The native archive resource generates ZIPs at Apply. The publisher copies the infrastructure root and its six-module dependency closure, without parent templates, publisher, providers, tests, state or private tfvars. Unsupported binary assets fail rather than being corrupted. Each ZIP has root main.tf/schema.yaml/modules plus:

- `recommendations_override.tf.json`: Terraform declaration defaults matching the generated schema. Console/environment edits take precedence.
- `inputs/infrastructure-spec.json`: the chosen option, model identity/revision/workload assumptions and template provenance. Files can exceed 8192 bytes without using an RMS input variable.
- `bundle-manifest.json`: option ID, expected region, publication/run identity and template/payload hashes. The final ZIP hash is returned in publication outputs.

The cluster picker/stack compartment remain dynamic. The actual RMS region is not replaced by a generated default. Expert edits to recommended hardware/storage appear in preview and invalidate the original sizing claim. Allocation rechecks live quantity-specific capacity and entitlement. Disk recommendations reserve two checkpoint copies plus 100 GiB, with a 200 GiB minimum; runtime cache sizing remains a model concern.

## Lifetime and ownership

Paths retain fixed model/region/shape folders, with timestamp/run/option identity only in the filename:

```text
models/org--model/us-phoenix-1/BM.GPU.A10.4/
  infrastructure-20261113T010000Z-<run-id>-<option-id>.zip
```

One Terraform publication record supplies Apply time and run identity consistently to all filenames, manifests and expiry values. Every Apply publishes fresh choices. PARs are object-scoped ObjectRead, default to 24 hours and allow 1–168 hours. Refresh/destroy can revoke older PARs and replace/remove older managed objects. This version does not provide append-only artifact history; retain a downloaded ZIP when needed. Discovery never owns the independent infrastructure state's GPU hosts. Create-stack links open new-stack wizards, not updates to existing stacks.

PARs grant access to their ZIPs, so restrict access to discovery outputs/state. The bucket stays private and bundles contain no credentials. Expired links require another Apply. Capacity remains a scan-time observation that can change before allocation.

## Verification boundary

Tests use the real archive provider and actual ZIPs, with OCI storage/PAR operations mocked. Extracted child tests cover defaults, a selected file larger than the RMS input limit, expert overrides, region rejection and no-allocation preview. An archive-only saved-Plan fixture runs Apply in a fresh directory without Plan-generated ZIPs. CI repeats these development checks. No Terraform configuration invokes nested Terraform.

Live upload/PAR download, IAM, authenticated RMS rendering/redirects and the complete workflow across RMS workers still need validation. No live storage/GPU resources were created during implementation. See [the broader bundle design](generated-deployment-bundles.md) for model-only work and remaining integration steps.
