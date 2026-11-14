<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Resource Manager discovery

Run `make package` and upload `work/packages/oke-llm-discovery.zip` to RMS with working directory `.`. Enter a public Hugging Face URL/ID, revision, context tokens and concurrent sequences per replica. Empty region/shape filters assess all READY subscribed regions and visible GPU shapes. Discovery allocates no GPUs.

## One clickable report

The only Terraform output is `comparison_report_url`. `schema.yaml` declares it as `type: link` and the primary output button. It opens a self-contained HTML report from the private discovery Object Storage bucket through an expiring ObjectRead PAR. RMS opens this page separately; it does not render the HTML inside the output console. The report is still published when no option is viable or ZIP publication is disabled.

The page contains:

1. Model identity, revision, type/architecture, layer and attention dimensions, Hub-published parameter/dtype counts, checkpoint formats/download size, license and source link.
2. Known resident-weight and KV-payload components for the entered context/concurrency, with dtype/margin assumptions. Complete estimates remain unknown where unsupported; the visible planning payload budget and its expandable formula are explicitly separate from hybrid cache/vision allocation.
3. Collapsed deployment options showing region/AD, exact GPU shape, observed supply, GPUs per replica, allocated hosts, packed replicas and unused GPUs. Expanded details include image, planned command, original upstream command, provenance, component requirements and separate infrastructure/model PAR and RMS links.
4. Positive reported regional capacity and per-AD entitlement evidence, including potential limit-increase requests where physical hosts exist even with zero quota. Zero-host and unknown-only rows stay in optional diagnostics. Aggregate-memory lower bounds do not establish a valid model layout or runtime. Zero physical capacity is not a limit-increase opportunity.

Counts for alternative shapes are not added together. Regional totals require unique complete whole-AD reports for the same exact shape; partial/conflicting coverage remains unknown. A positive report is a snapshot, not a reservation. All generated serving configurations still require runtime validation.

Recommendations use hardware fit first: more VRAM per GPU, less per-replica sharding, RDMA-capable hardware, then additional complete replicas covered by both capacity and entitlement in the selected AD. Regional physical supply and fewer allocated GPUs break later ties. Display sorting is independent of this policy. VRAM is a fit proxy; bandwidth, compute and actual throughput still require hardware validation. No future capacity or RDMA placement is reserved.

Report JSON, scripts and Redwood styling are embedded in the page. Opening, filtering or expanding it makes no new discovery requests. `include_diagnostics=true` adds a collapsed evidence section, without enabling unused engine/cache lookups. There are no duplicate public JSON outputs.

The style tokens and shell come from the supplied `oci-design-system-redwood-jet` package; the report uses native HTML controls with module-owned layout styles and no JET runtime or CDN dependency. Oracle documents [RMS schema types and output controls](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/terraformconfigresourcemanager_topic-schema.htm).

## Deploy from the page

Each confirmed option has **both** deployment ZIPs immediately:

- **GPU pool and shared components:** choose an existing cluster in the indicated region, review Plan and provision retained infrastructure. Skip this when reusing a suitable platform. Existing CPU pools run controllers; GPU allocation is managed only here.
- **Model project and pipelines:** select the cluster. The stack creates a separate project/environment/repositories/pipelines for the model and infers matching pool/networking. It can be created before GPUs/controllers exist; execution waits for trusted namespace onboarding and real readiness. Ambiguous pool/network choices have optional advanced overrides.

Neither clicking a link nor creating a model stack starts inference. Model deploy/validate/benchmark/undeploy are explicit operations. See [model target and access](model-binding.md).

For local use:

```sh
terraform init
terraform plan -var-file=/path/to/request.tfvars.json -out=work/discovery.tfplan
terraform apply work/discovery.tfplan
terraform output -raw comparison_report_url
```

Disabling `publish_infrastructure_bundles` omits both sets of stack ZIPs, while still creating the assessment page. Report and stack links share a publication expiry; reapplying discovery publishes a new snapshot and can replace old objects/PARs. Rebuilding a local ZIP alone does not change existing RMS stacks or links.

## Work performed once

| Operation | Work per scan, excluding pagination/retries |
|---|---|
| Region subscriptions | One response supplies region list and home region |
| AD inventory | One list per selected region |
| GPU shapes | One listing per AD/compartment; reuse when target equals tenancy root |
| Limit definitions and values | One list each per region with relevant GPU quota names |
| Entitlement headroom | One request per relevant quota/scope |
| Physical capacity | One batched report per AD with assessed GPU shapes |
| Recipe metadata | One shared response per model |
| Recipe rendering / image metadata | Distinct required queries only; reuse exact resolved references |

Configured limits, effective compartment headroom and physical host capacity are separate necessary checks. Unrelated quota calls, unused nightly/cache alternatives and rendering for unavailable hardware are skipped. Later new-allocation admission rechecks the selected AD/shape and relevant regional/global quotas; model reuse does not allocate new hosts.

RMS regional lookup uses the tested OCI CLI/Bash/jq helper with principal/delegated authentication. Public model/recipe profiling uses Terraform HTTP/HCL. There is no nested Terraform or custom Python/Go discovery program. Discovery owns only publication storage, ZIPs, HTML and PARs; it creates no nodes, controllers or DevOps projects.
