<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

# Model-to-deployment implementation plan

Approved direction: native Terraform discovery and candidate planning, selected deployment variables, retained GPU allocation, and DevOps deploy/validation/benchmark pipelines. Existing OKE first. Interpreter scripts are permitted in packaging and DevOps jobs; RMS discovery remains native providers/HCL.

## Phase 1 — requirements and catalog
- [x] Add SHA-pinned model-card reads with bounded regex evidence for explicit vLLM/SGLang version requirements; preserve unspecified/unknown outcomes.
- [x] Expose structured attention and checkpoint information needed for layout planning.
- [x] Add sourced GPU VRAM/topology and versioned engine-image catalogs.
- [x] Define supported-layout policy and assessment status contracts.

## Phase 2 — candidate planning and selection
- [x] Match model memory and engine requirements to per-rank GPU layouts and AD capacity without summing overlapping supply.
- [x] Keep quota headroom, hardware capacity, memory feasibility and runtime validity distinct.
- [x] Integrate candidate/rejection results into discovery and export selected deployment.tfvars.json after selection.
- [x] Validate unknown dimensions, unsupported architectures/formats, insufficient per-rank memory, TP/KV replication, version constraints and stale/missing observations.

## Phase 3 — deployment infrastructure
- [x] Add existing-cluster GPU pool allocation, explicit RDMA compute-cluster path and retained-allocation safeguards.
- [x] Recheck selected capacity and shape/cluster/image compatibility before allocation.
- [x] Create OCI DevOps project, logging, environments, artifacts/pipelines and documented IAM prerequisites.

## Phase 4 — delivery and verification
- [x] Add a pinned serving recipe and CPU/CRD/operator prerequisites as required by that recipe.
- [x] Deploy pinned model and image with selected topology and request settings.
- [x] Add automatic readiness, inference, streaming and topology checks.
- [x] Add explicitly triggered benchmark pipeline with controlled inputs, latency/throughput/error measurements and provenance artifacts.
- [x] Verify manifests/scripts and Terraform with mocks plus local/live read-only checks; document cloud/GPU checks that need a selected target.

## Phase 5 — catalog packaging
- [x] Build a bounded HF catalog refresh/package hook, keep publisher/family overrides and generate RMS model choices with a custom-ID path.
- [x] Validate generated schema/catalog consistency and native curated/custom resolution.

Validation boundaries: do not allocate billable GPUs without a selected deployment target. No synthetic check is reported as GPU/RMS runtime validation. Unknown models produce an assessment prompt, not fabricated compatibility. Conversation persistence is a distinct API-layer capability and must not be claimed from KV cache reuse.

## Remaining live validation
- [ ] Select a real regional OKE target, images and subnets; review the allocation plan.
- [ ] Run both stacks in RMS and verify their forms.
- [ ] Run DevOps deploy/validation/benchmark against GPUs, including RDMA when selected.

Local verification includes Terraform mocks, released Helm chart rendering, schema/catalog/selection checks and benchmark command construction. The official benchmark container has not been executed locally because the Docker daemon is unavailable. No GPU allocation was attempted.

## Local verification and cleanup — November 11, 2026

- Isolated feature branch: 38 native Terraform test runs passed across model profile, inventory, capacity, planner, allocation, DevOps and both roots.
- Shared checkout including the independently developed quota feature: 53 Terraform test runs passed.
- Six command/manifest/schema/selection tests passed, including rendering the released production-stack chart. The benchmark executable was stubbed for command construction; its container was not run.
- The committed-source ZIP passed integrity/exclusion checks. Both stack roots initialized and validated after extraction; no state, private discovery data, tests, Node dependencies or obsolete benchmark client entered the package.
- Removed the custom benchmark client/tests, installed node_modules/npm cache, obsolete Python bytecode directories, and disposable render outputs. Retained source tests/dev dependency manifests, provider caches needed by initialized Terraform, and private discovery evidence.
- Feature changes are committed on `feature/model-to-deployment-workflow`. The original feature branch remains available. The user subsequently requested consolidation of all built work into main after combined local validation; no live GPU allocation was performed and end-to-end cloud validation remains pending.

Consolidation verification: the combined implementation passed 53 Terraform tests and six command/manifest/schema tests before integration into local `main`. Serving and quota feature histories are preserved; no remote push or cloud deployment was performed.

## RMS packaging and candidate explanations

- [x] Phase 1: inspect the saved discovery result and distinguish model/engine blockers from physical capacity.
- [x] Phase 2: add root Make targets for separate discovery/deployment ZIPs, preserving relative dependencies and committed-source provenance.
- [x] Phase 3: expose blocking reasons and evaluated-layout count; test unsupported architectures with positive hardware observations.
- [x] Phase 4: document RMS Outputs versus exact JSON state extraction, and refresh outdated workflow guidance.
- [x] Phase 5: build/inspect both packages and validate their extracted Terraform roots. Actual RMS UI/job execution remains separate live validation.

Packaging verification: both Make targets produced isolated, integrity-checked ZIPs with state/private files/tests excluded. Both extracted stack roots initialized and passed Terraform validation. Planner tests passed 13 runs, including unsupported Flint architecture with positive capacity/headroom. Flint runtime support remains unimplemented in this stack despite upstream support; its specific image/recipe, hybrid-attention estimate and hardware coverage still need integration.

## Optional RMS scope filters
- [x] Inspect root defaults and RMS schema; retain all-region/all-shape behavior.
- [x] Make schema filters explicitly optional with empty defaults; normalize explicit Terraform nulls to defaults.
- [x] Test omitted/null values and schema defaults; rebuild the discovery ZIP.

The reported RMS job error has not been inspected. These changes harden the optional-input contract; a literal `var.shapes` error cannot originate from this root, which declares `shape_names`. Actual RMS verification requires the failing job details.

Verification: ten Node tests and four discovery Terraform tests passed, including omitted/null filter values. The rebuilt ZIP was inspected for explicit optional schema defaults and non-null Terraform defaults. Exact failing RMS job details remain needed to establish its cause; no live RMS job was run for this change.

## RMS form controls and regional scan investigation
- [x] Check Oracle's schema specification against group references, region context and complex list controls.
- [x] Correct group entries to plain field names in both schemas; define a visible session-default bootstrap region and typed list controls in discovery.
- [x] Test field references/control definitions and rebuild both packages.
- [ ] Confirm the corrected form/job in RMS; the existing form and failed job log were inspected.

The previous optional-default fix did not address these schema/control defects. Native Compute endpoints remain regional. Standard Terraform cannot dynamically instantiate OCI provider aliases from subscribed-region data. Automated pre-job generation or a dynamic CLI/custom-provider query mechanism are distinct options; no regional architecture replacement is assumed without resolving that tradeoff.

Confirmed diagnosis: the saved RMS `regions` and `shape_names` values are empty strings, producing `Missing expression` before defaults can apply. Bootstrap `region` is populated. The existing form shows an unavailable empty dropdown for its generic array controls. Eleven local command/catalog/schema/manifest tests passed, including field-reference completeness, visible bootstrap region and typed list definitions. No corrected RMS form/Plan validation has yet run. Auto-review rejected changing the external stack without explicit user authorization; no cloud variables were changed.

## Dynamic SDK discovery
- [x] Phase 1: package a Go OCI SDK lookup using the standard external data-source protocol; honor RMS instance-principal/delegated authentication, resource-principal environments or local DEFAULT config.
- [x] Phase 2: enumerate READY subscriptions and query regional ADs, GPU shapes, limits/headroom and capacity using bounded concurrency and pagination. Preserve the existing planner input contract and explicit unknown/error states.
- [x] Phase 3: replace discovery aliases with one dynamic lookup, package platform-specific binaries, and preserve legacy native modules for allocation/examples.
- [ ] Phase 4: test SDK request/response processing, auth/error handling, scopes, protocol and Terraform contracts; validate live discovery and RMS packaging.

The user selected dynamic SDK discovery. A compiled Go helper behind hashicorp/external avoids Python/CLI dependencies and a separate RMS custom-provider bucket. It performs fresh diagnostic capacity-report requests during reads/Plan, never GPU allocation. Artifact provenance/checksums and runtime architecture must be explicit. Deployment allocation remains native OCI Terraform.

Local SDK verification: seven Go tests, five root Terraform tests, and eleven command/catalog/schema/manifest tests passed. A live SDK run enumerated all 16 READY subscriptions including Chennai/Delhi and requested 19 diagnostic reports. A separate live Terraform model-profile/SDK/planner flow for Qwen2.5-0.5B on Melbourne A10 returned 14 analytical candidates and one positive capacity/headroom observation. No instances were allocated. The first authorized RMS Plan returned INTERNAL_SERVICE_ERROR without Terraform logs; corrected filter values were saved successfully. Model UI now uses URL/ID directly, preserving legacy selections but prioritizing explicit model input. Native discovery state needs deliberate migration if it contains old provider aliases.


## Direct model input and RMS execution validation
- [x] Replace the unwieldy catalog dropdown with a public Hugging Face URL/model-ID field; retain the alphabetical recipe reference and hidden legacy selection compatibility.
- [x] Validate explicit model priority and RMS schema controls locally.
- [x] Package both Linux architectures and restore executable permissions after RMS extraction.
- [x] Honor RMS authentication mode and delegated caller tokens without persisting credentials or verbose SDK request logs.
- [x] Complete a real RMS discovery Plan: all 16 READY subscribed regions were assessed. No GPU instances were allocated. Flint still has zero analytical candidates because engine/estimator coverage is separate from capacity.
- [ ] Verify the revised form visually; the Resource Manager console remains blank even on its stack-list page in the inspected browser session.
- [x] Inspect the actual RMS execution host: OCI CLI, Python 3.9.25 and OCI Python SDK 2.189.0 are installed. A Go executable is not required for this environment. The simpler replacement is a Terraform external shell helper invoking OCI CLI with regional and delegated-auth settings; that replacement is not implemented yet.

Nine Go test functions (including auth-mode and delegated-token cases), five discovery Terraform tests and twelve Node checks passed. Both stack ZIPs were rebuilt and the discovery archive passed integrity validation. The model URL/ID field and dynamic scan are on the feature branch; no main merge has been made while the user reviews the execution approach.

## OCI CLI replacement and Flint gap assessment
- [x] Phase 1: replace the Go data-source helper with Bash/OCI CLI/jq, preserving planner JSON, scoped discovery, pagination, unknown capacity and delegated RMS authorization.
- [x] Phase 2: exercise CLI fixtures and live local discovery; remove obsolete Go source, launchers and binary packaging once replacement checks pass.
- [x] Phase 3: package and run a Plan against the existing RMS discovery stack; verify real cross-region output without allocating GPU nodes.
- [x] Phase 4: inspect Flint's pinned recipe, released engine support, hybrid-attention memory/layout constraints and GPU coverage; document exact blockers and the work required rather than treating a model-list entry as deployment validation.

CLI replacement pre-cloud checks: six CLI fixture tests and five discovery Terraform tests passed; the complete Node suite passed before the added complete-batch regression, which then passed separately. A live Melbourne/A10 CLI run queried compartment headroom and physical capacity and matched the previous SDK inventory/capacity/shape JSON keys. Its current capacity response was OUT_OF_HOST_CAPACITY (zero), preserved as observed rather than treated as a software failure. Go sources/build launchers/binary packaging were removed. Flint requirements and remaining implementation gaps are documented in docs/flint-assessment.md.


CLI RMS validation completed successfully: the Plan assessed all 16 READY subscriptions, made 26 compartment headroom queries and returned 19 diagnostic AD capacity reports. Downloaded JSON is retained privately at work/cli-rms-discovery-plan.json. No GPU instances were allocated. Flint retains exactly the two software blockers: estimator coverage and reviewed engine coverage; this change does not bypass them. The tested stack uses Bash/OCI CLI/jq only. Go binaries, source, build launchers and repository-local Go caches have been removed; installed Node dependencies used for checks were removed after verification. The revised RMS model form remains visually unverified because the console's Resource Manager pages were blank in the inspected session.

## Runtime recipe/image resolution and expert deployment
- [x] Phase 1: fetch the selected vLLM recipe during discovery at a resolved source SHA; extract variant/base/selected-feature args and environment, tested hardware/strategies and version evidence without executing recipe prose.
- [x] Phase 2: resolve supporting stable/nightly images dynamically, prefer stable when its source registry declares the architecture even if an older recipe says nightly; freeze an image digest/platform and explain unknown requirements.
- [x] Phase 3: report memory-only GPU alternatives separately from reviewed serving configurations and expose tested-hardware/limit gaps. Preserve estimator uncertainty and require expert-provided topology/rank memory when needed.
- [x] Phase 4: carry the frozen recipe/engine/args into deployment, provide an explicit expert configuration path, and test discovery-to-render handoff including missing recipes, nightly fallback, stale version hints and unmatched hardware.
- [x] Phase 5: run live model/recipe/image lookup and an RMS discovery Plan; package, document and commit verified work. No GPU allocation or runtime validation is implied.


Local runtime-resolution evidence: native HTTP/HCL lookup for RecursiveSI/flint selected the v0.33.0 amd64 platform digest, retained the recipe nightly hint and extracted requested reasoning/tool arguments. Combining that profile/resolution with the saved 16-region inventory produced 56 aggregate-sizing options and a GB200/ARM64 recipe target. These are undetermined configurations, not executable/validated layouts. Nine resolver tests, 14 planner tests, eight model-profile tests, seven deployment-root tests and five discovery-root tests passed. Nineteen Node checks passed; selected updated selection/render checks then passed, including actual released-chart rendering with frozen flags/environment. No GPU deployment occurred. The live RMS Plan for the new combined feature remains next.


Combined RMS Plan succeeded for BF16 Flint across all 16 subscribed regions. The downloaded plan freezes vLLM 0.33.0 linux/amd64 at digest sha256:91ee972ab751fb7180bc71c175865e36b091686600dca783d52b2511399810b3, records the recipe's nightly hint, identifies GB200/ARM64 as the upstream target and exposes 56 undetermined aggregate-sizing options. Status is expert_options_available; no automatic per-rank Flint layouts are claimed. Evidence is retained privately at work/runtime-resolution-rms-plan.json. No GPU nodes, DevOps deployment or benchmark were run. An additional render regression verifies digest-pinned expert images with registry ports, explicit tags and custom version labels. Source is committed and packaged; local-main integration follows validation.
