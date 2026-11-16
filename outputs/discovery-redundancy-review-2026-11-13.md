<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

# Discovery redundancy review

Date: November 13, 2026. Scope: the current working tree, including uncommitted changes, based on commit `80660e3`. This is a source and dependency review; no live OCI discovery, Terraform Plan/Apply, or performance benchmark was run. Existing source changes were left untouched.

## Conclusion

The concern is partly correct: there are redundant outputs **and actual avoidable operations**. However, the root does not run every discovery module found in the repository. It runs one CLI-based OCI scanner. Native inventory/capacity modules are retained for allocation admission and examples; copying those modules into ZIPs does not execute them.

User clarification: publication of every option is required so any option can be selected. Keep every option's PAR and RMS link. Legacy handoffs are approved for removal. Preserve configured-limit, effective compartment headroom and physical-capacity checks for all offered GPU choices. The quota optimization below concerns requests unrelated to those choices, not removal of these checks.

The default workflow should expose a compact list of all launch options: RMS URL, PAR/download URL and expiry, selection summary, and a useful failure reason when nothing can be offered. Large reports and the older JSON handoffs should leave the default user experience.

Removing output blocks alone primarily reduces display, serialization and root-output state duplication. Real runtime savings require changing which data sources and resource instances are configured. The best candidates are unused engine alternatives, exploratory cache lookups, duplicate recipe requests and unrelated quota-headroom calls. Publication of all choices is useful required work.

## What actually runs

```text
Root discovery
  model-profile                  Hugging Face metadata/config/card; optional recipe fallback
  serving-resolution             Recipe metadata/YAML, vLLM source and image metadata
  oci-discovery                  One external program; regional OCI CLI scans
  deployment-planner             Local layout/availability calculations plus recipe/image HTTP
  control-plane-sizing           Constant HCL output, no remote discovery
  deployment-handoff             Local legacy JSON serialization, no remote discovery
  infrastructure-publisher       ZIP generation, private bucket, objects and PARs

Later, independently applied infrastructure stack
  deployment-target              Selected cluster, networking, add-ons and image lookup
  gpu-allocation                 Native inventory + selected capacity/admission checks
  platform-bootstrap             Shared platform resources
```

Evidence: [root module calls](../main.tf), [publication wiring](../publication.tf), [CLI scanner](../modules/oci-discovery/scripts/discover-oci.sh), [infrastructure root](../templates/infrastructure/main.tf).

The publisher reads template/module files as archive content. It does not apply those modules in the discovery state. Likewise, `templates/deployment` being embedded in the entry ZIP does not run its resources.

## Findings and improvements

| Priority | Finding | Current overhead | Recommendation |
|---|---|---|---|
| High | Nightly engine alternatives are assessed even when unused by root planning | Up to three additional HTTP reads when stable is selected; extra failure dependencies | Disable alternative assessment in the normal launch path |
| High | Cache/offload alternatives are fetched without being selected | Two HTTP reads per valid hardware key when CPU offload is not declared unsupported | Fetch only for an explicitly requested cache feature, or in diagnostic mode |
| High | Recipe metadata and some rendered requests are duplicated | Repeated HTTP work and possible inconsistent observations | Resolve once and pass a shared result; deduplicate rendered requests by full query |
| Keep | Every eligible candidate/suggestion becomes its own published bundle | ZIP rendering, two uploads and one PAR per option, on every Apply | Preserve every selectable option and its launch link |
| Medium | Headroom queries can include unrelated GPU-named limits | One headroom call per supported extra limit/scope | Retain all relevant limit/headroom/capacity checks; omit only queries not used by the offered shapes |
| Medium | Multiple output and handoff formats overlap | Large outputs/state and local JSON work | Keep a compact launch contract; move legacy/debug output to a separate path |
| Medium | Allocation admission inventories more than the selected AD | Additional AD shape and limit-headroom reads in the child stack | Retain fresh checks but narrow them to the selected AD/shape/compartment |
| Low | Unreferenced regional scan wrapper duplicates discovery logic | Maintenance/package overhead; no root runtime cost | Retire or isolate it after checking external consumers |

### 1. Unused engine alternatives are real network work

[Root serving resolution](../main.tf) explicitly sets `assess_alternatives = true`. In [serving-resolution](../modules/serving-resolution/main.tf), that enables nightly commit, registry and alternative-image requests even when stable is already selected. Their alternative result is placed in `resolution.engine_candidates`.

The root planner is passed only `resolution.engine`, not `engine_candidates`. The older combined deployment template does consume the alternatives, which explains their existence, but they do not expand the root's normal infrastructure recommendations.

Set alternative assessment false for the launch workflow. Preserve nightly lookup when automatic resolution actually needs nightly. On a stable-selected path this removes three configured HTTP reads; it does not remove the stable/nightly selection safeguards.

### 2. Cache-option lookups are exploratory and can block the main workflow

[Planner recipe API](../modules/deployment-planner/recipe-api.tf), `data.http.cache_option`, requests both `simple` and `lmcache` for each valid hardware key when `offloading_cpu` is not `unsupported`. The results only enter `assessment.recipe_options.cache_options`; they do not choose the published option or configure its infrastructure defaults. The module itself labels them `requires_cache_integration`.

These are unnecessary for obtaining the current launch bundle. Their HTTP postconditions can fail an otherwise usable discovery job. Gate the data sources themselves behind explicit feature selection; suppressing the output would leave the requests configured.

### 3. Recipe resolution has overlapping owners

[Serving resolution](../modules/serving-resolution/main.tf) and [planner](../modules/deployment-planner/recipe-api.tf) both fetch `https://recipes.vllm.ai/<model>.json`. [Model profiling](../modules/model-profile/recipe-fallback.tf) can fetch it a third time when `config.json` is absent. Separate Terraform data-source blocks should not be treated as a shared HTTP cache.

There is also duplicate rendering work: A10, A100 and L40S keys can all map to the same `h100` API query. `for_each = local.api_hardware` retains separate request instances for those keys. Cache-option requests repeat this mapping pattern.

Establish one recipe metadata owner, then pass its result to the other consumers. Fetch renderings once per unique hardware/variant/strategy/features query and map them back to OCI shapes. Preserve pinned source identity and existing validation. This also avoids mixing independently fetched recipe snapshots within one result. Handle the profile-fallback dependency carefully so the refactor does not introduce a Terraform cycle.

### 4. Publication of every option is required

[Publication](../publication.tf) merges **all analytical candidates and recipe suggestions** into `infrastructure_options`, keyed by option ID. [The publisher](../modules/infrastructure-publisher/main.tf) creates, for each entry:

- One archive resource.
- One descriptive Object Storage ZIP.
- One identical short-path launch ZIP.
- One object-read PAR.

For N options, that is N archive instances, 2N uploaded objects and N PARs, plus shared bucket/bookkeeping resources. The publication trigger uses `uuid()` and `timestamp()`, deliberately causing fresh publication on subsequent Applies. Existing managed objects/PARs can be replaced or revoked.

Keep these operations for every offered option, as requested. Do not reduce publication to the recommendation or merge away distinct model/serving choices. The fact that multiple options can request similar infrastructure does not make offering all of them unnecessary.

The short-path copy exists for a documented RMS `ZipOrigin` URL-length problem. Keep the short path. If browsable descriptive copies are not a product requirement, use the short object as the sole ZIP and retain provenance in metadata/manifest. That reduces uploads from two per option to one without making the launch URL longer.

Consider separating explicit link renewal from ordinary unchanged reruns. Refreshing capacity and renewing PARs are different operations; avoid introducing automatic reuse of stale capacity claims.

### 5. Retain the quota/limits/capacity chain; filter only unrelated queries

The CLI scanner defaults to every READY region and every visible GPU shape. Its JQ [limit plan](../modules/oci-discovery/scripts/lib/oci-discovery.jq) also includes GPU-named limits not mapped to visible shapes when no shape filter is supplied. With `only_shapes_with_limits = false`, those can generate headroom requests; the budget is 1000 per region.

The exact expansion is `limit_plan` in `modules/oci-discovery/scripts/lib/oci-discovery.jq:13`: it includes either a name in the shapes' `quota_names`, **or any name containing `gpu` when no shape filter is set**. The loop in `modules/oci-discovery/scripts/discover-oci.sh:113` then makes individual headroom requests. The planner later consumes only matching shape quota names (`modules/deployment-planner/main.tf:46`), leaving those unrelated observations unused for launch eligibility.

Keep the bulk limit-definition/value listings. Keep headroom calls for every applicable quota name and scope for each offered shape. Keep the physical capacity reports. The removable portion is only the extra per-limit headroom calls whose names are absent from all discovered target-shape quota mappings. Validate that mapping coverage remains complete; an unknown mapping must remain unknown and must not become eligible.

These checks answer different questions:

1. Configured limit: is this resource allowed, and what is its ceiling?
2. Resource availability: how much usable entitlement remains for the intended compartment and scope after usage/quota constraints?
3. Compute capacity report: does OCI report enough physical hosts of this shape in this AD?

All three are needed. For example, an eight-GPU host needs eight GPUs of headroom even when TP uses only two. A positive configured limit or positive physical capacity alone is insufficient.

Capacity reports are already batched across shapes: usually one report request per AD with assessed shapes, **not one request per shape**. Removing shapes mostly shrinks the report payload; skipping an entirely ineligible AD removes a report call. `only_shapes_with_limits = true` already skips shapes with known zero applicable limits, at the cost of losing physical-capacity evidence for limit-increase recommendations.

Target-compartment and tenancy-root shape listings are deliberate: the former feeds entitlement-visible inventory; the latter feeds physical-capacity discovery. They already reuse the listing when both compartments are the root. Do not collapse them without preserving those semantics.

Keep all-region/all-shape discovery and the current zero-limit capacity diagnostics unless a separate product decision changes them. Narrow only demonstrably unused headroom requests. `only_shapes_with_limits` is not a precise fix for unrelated queries: it also suppresses zero-limit capacity observations, so changing its default would change available diagnostics.

### 6. Several outputs serve the older workflow

| Root output | Role today | Proposed treatment |
|---|---|---|
| `recommended_launch_url` | Primary RMS button | Keep |
| `deployment_options` | PARs, alternate URLs and provenance | Keep every selectable option |
| `deployment_option_count` | Small user-facing count | Keep |
| `recommendations` | Another projection of suggestions | Fold a concise summary into the launch result |
| `assessment` | Full planner report | Optional diagnostic artifact/path |
| `discovery` | Profile, serving result, assessment and regional observations | Optional diagnostic artifact/path |
| `deployment_inputs` | Large tfvars handoff for the combined deployment template | Remove; user approved retiring legacy handoffs |
| `deployment_handoffs` | Per-choice inline/Object Storage JSON for the combined deployment template | Remove with the root handoff module and obsolete consumers/docs |

The current publisher takes profile/model data and planner options directly. It does not consume either legacy handoff output or `module.handoff`. Removing that module from the normal root removes local encoding, hashing and byte-budget work; it does not remove OCI discovery calls.

There are also three constant `control-plane-sizing` module instances in the root module tree: direct, planner and handoff. These are repeated HCL constants, **not three CPU discovery scans**. Consolidation is a clarity improvement with negligible remote runtime impact. The generated infrastructure stack uses its own bootstrap CPU budget.

Keep a small always-available failure summary. A workflow exposing only null links would make capacity, missing quota and unsupported model cases hard to diagnose. Moving detailed reports into Object Storage can help the user interface, but does not automatically remove provider response bodies or observations from Terraform state.

### 7. Rechecking at allocation time is justified; its breadth can improve

[GPU allocation](../modules/gpu-allocation/main.tf) calls native inventory and capacity modules again in the independent infrastructure stack. This is needed because capacity/headroom can change after the discovery job, and the user can edit generated defaults. Removing those checks would weaken allocation admission.

However, [accelerator-inventory](../modules/accelerator-inventory/main.tf) lists subscriptions and all ADs, lists shapes in every AD, then queries relevant limits across those observations. Allocation only needs the selected shape and AD. Add a focused admission path or an AD scope so the later check remains fresh without repeating regional inventory. It also repeats some cluster/add-on/node-pool lookups made by `deployment-target`; pass existing observations where appropriate within a single child-stack run.

### 8. Some redundancy is dormant code and packaging only

No checked-in caller of `regional-capacity-scan` was found. If invoked, it separately lists subscriptions/ADs/shapes while also invoking `accelerator-inventory`, which lists them again. Retire it if no external consumers require it, or remove its duplicate discovery by consuming the inventory result. Keep native inventory/capacity modules: the allocation stack actively uses them.

[Packaging](../scripts/package-stack.sh) copies every module, both downstream roots, docs and outputs into the discovery entry package. This increases package size and the surface people must understand; it does not run all included Terraform configurations. A dependency allowlist and a separate legacy deployment package would simplify distribution. Preserve everything the publisher needs to render its downstream ZIPs.

Documentation needs reconciliation: `docs/oci-discovery.md` still contains native-root/provider-alias and runtime statements contradicted by the CLI root, and `schema.yaml` says reusing `observation_id` preserves the snapshot, whereas the CLI scans when its external data source is read. These statements help create the impression that several discovery mechanisms are simultaneously active.

## Cost model and limits of the assessment

Ignoring pagination, retries and authentication internals, the CLI issues approximately:

`S + sum over regions [3 + A × (1 + D) + H + C]`

Here S is one or two subscription lookups, A is the number of ADs, D is 1 when target compartment differs from tenancy root and otherwise 0, H is the number of headroom queries (up to 1000), and C is the number of ADs needing capacity reports (at most A). The fixed three calls are AD listing and limit definitions/values. Regions run in batches of four; calls inside each region are largely sequential.

This makes relevant-headroom filtering a likely larger OCI runtime saving than deleting output blocks. The planner also enumerates roughly `shape/AD rows × usable engines × 4 TP values × max_nodes_per_replica` analytical layouts locally. That is real local work, but no timing evidence here establishes it as the bottleneck. Measure request counts, bytes, archive counts and phase durations before claiming a percentage speedup.

## Suggested implementation sequence

### Phase 1 — remove work with little product impact

- [ ] Disable unused engine alternatives in the normal root.
- [ ] Gate exploratory cache lookups on explicit selection.
- [ ] Fetch shared recipe metadata once and deduplicate equivalent rendered queries.
- [ ] Limit normal headroom queries to applicable shape quotas.
- [ ] Correct stale discovery/schema documentation.

Verify with mocked HTTP/CLI request counts, unchanged launch specifications for representative supported models, and clear behavior for absent recipes, missing config fallback, zero/unknown quota and API failures.

### Phase 2 — simplify the launch contract and publication

- [x] Confirm every option must remain published and selectable.
- [ ] Preserve each option's configuration and evidence while simplifying the output presentation.
- [ ] Return compact launch metadata and a clear no-option reason.
- [ ] Remove approved legacy handoffs; update consumers, documentation and tests. Keep detailed diagnostics separately as needed.
- [ ] Decide whether the descriptive duplicate ZIP is worth retaining.

Also fix an existing edge case: `recommended_selection_id` is chosen only from recipe suggestions, while publication includes analytical candidates too. If only candidates exist, bundles can be published with a null primary launch URL. Either define a suitable explicitly qualified fallback or explain why no primary recommendation is available.

Verify actual ZIP contents/defaults, PAR expiry and short URL length, selection of every published alternative, and the RMS import flow through variable review. Plan a state migration before removing existing object/PAR resources, since that can invalidate issued links.

### Phase 3 — reduce downstream and maintenance duplication

- [ ] Scope fresh admission checks to the chosen AD/shape.
- [ ] Reuse cluster observations within the child stack where appropriate.
- [ ] Isolate the legacy combined template and retire the unused regional wrapper if safe.
- [ ] Package only the dependency closure needed by supported workflows.

Verify quantity-specific quota checks and fresh capacity admission still reject unsafe allocations; run extracted-package checks and validate the selected child flow end to end.

## Terraform behavior references

HashiCorp describes [outputs](https://developer.hashicorp.com/terraform/language/block/output) as exposed return values, and [data sources](https://developer.hashicorp.com/terraform/language/data-sources) as external queries normally read during refresh/planning or deferred to Apply. This distinction is why hiding report outputs is separate from disabling the operations that produce them. Applying a saved plan does not imply an additional fresh scan of every already-read data source.
