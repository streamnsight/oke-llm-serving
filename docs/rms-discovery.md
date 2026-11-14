<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Resource Manager discovery

`make package` produces `work/packages/oke-llm-discovery.zip`. Upload that ZIP with working directory `.`. It contains grouped `modules/` and the infrastructure/model templates. CI publishes only this entry ZIP. Root build tools, development tests, state, request files and node_modules are excluded.

Enter a public Hugging Face URL/ID, revision, context tokens and concurrent sequences per replica. No catalog selection or deployment flags are needed. Empty region/shape filters mean every READY subscribed region and visible GPU shape. The scanner discovers the tenancy home region from its authenticated principal/profile; the optional hidden region is only an initial endpoint hint.

## One result

RMS displays `discovery`, one consolidated JSON with:

- `model`: immutable identity, workload assumptions, declared checkpoint size and nullable memory estimates.
- `options`: every confirmed choice, including shape/AD/region capacity, entitlement, allocation, replica packing, memory and full launch/download URLs.
- `regional_capacity`: exact-shape totals and assessed-AD coverage, without adding alternative shapes or quota ceilings.
- `failure_summary`: useful reasons when no deployable choice is offered.
- `diagnostics`: null by default; `include_diagnostics=true` exposes existing detailed evidence without enabling exploratory scans.

The count and two URL outputs are navigation aids. **Compare all options** opens a separate HTML page via Object Storage PAR; RMS does not render it. The native JSON contains all the same choices and links and remains usable without HTML. The secondary recommendation link chooses one option; all other links remain selectable.

## Obtain JSON

Locally:

```sh
terraform output -json discovery > work/discovery.json
jq '.model, .options' work/discovery.json
```

In RMS, inspect the job's Outputs or retrieve its Terraform state through the API:

```sh
oci resource-manager job get-job-tf-state --job-id "$JOB_ID" --file work/discovery.tfstate
jq '.outputs.discovery.value' work/discovery.tfstate > work/discovery.json
```

No large JSON is pasted into downstream RMS variables. Discovery publishes configured infrastructure ZIPs; infrastructure subsequently publishes a model ZIP bound to its actual IDs. HCL declaration defaults and schema defaults match, so Console edits remain effective.

## Required work, without duplicate scans

The root owns one recipe metadata response and supplies it to model profiling, serving resolution and hardware planning. Hardware render queries run only for GPU types with positive reported capacity and entitlement for at least one whole host. Identical queries share one request; an already-resolved exact image tag/SHA is reused. Unselected nightly/cache alternatives are not fetched. Missing recipes preserve explicit uncertainty rather than probing guessed paths.

Regional discovery invokes one module-owned OCI CLI/Bash/jq scanner. One subscription response supplies both the home region and the region list. Each region lists limits once, queries each relevant quota/scope once and batches all assessed shapes into one capacity report per AD. Shape listings for the target compartment and tenancy root have different visibility purposes; when they are the same compartment, the response is reused.

| Operation | Work per scan, excluding pagination/retries |
|---|---|
| Region subscriptions | One response for the tenancy |
| AD inventory | One list per selected region |
| GPU shapes | One listing per AD/compartment; reuse when target equals tenancy root |
| Limit definitions and values | One list each per region with relevant GPU quota names |
| Entitlement headroom | One request per relevant quota/scope |
| Physical capacity | One batched report per AD with assessed GPU shapes |
| Recipe metadata | One shared response per model |
| Rendered recipe and image metadata | One per distinct required query/reference, reusing resolved evidence |

Regions with no relevant GPU quota names skip limit-list requests. Regions/ADs without assessed GPU shapes make no capacity-report request. No separate scan is run to produce the comparison report or diagnostic output.

A configured limit, effective compartment headroom and currently reported physical host capacity are all required for offered options. Unrelated GPU-named quota entries are omitted. Later native allocation admission makes fresh checks for only the selected AD/shape and its relevant regional/global quotas; it does not repeat the all-region scan. It needs no subscription or AD-list lookup because those choices are already known. This later check remains necessary because discovery is not a reservation and users can edit deployment quantities.

RMS runtime requires OCI CLI, Bash and jq for dynamic regional lookup; the tested RMS worker supplies them. Public model/recipe profiling uses Terraform HTTP/HCL. There is no custom Python/Go program or nested Terraform execution.

Discovery itself creates only bundle/report storage and PARs. It creates no GPU/CPU nodes, controllers or DevOps pipelines. See [publication](infrastructure-publication.md), [infrastructure bootstrap](infrastructure-bootstrap.md) and [model binding](model-binding.md).
