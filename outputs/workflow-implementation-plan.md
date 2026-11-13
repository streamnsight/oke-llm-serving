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

## Default discovery to tenancy home region
- [x] Hide the internal initial-connection region; make local region input optional.
- [x] Discover the home region from OCI subscription metadata, use it for the subscription lookup and expose it in discovery output. Retain all-READY regional scanning.
- [x] Verify home-region routing, absent local overrides and the hidden RMS form contract; run a live scoped CLI check, package and commit.

Home-region verification: seven CLI tests, six discovery Terraform tests and the hidden-context schema check passed. A live scoped CLI run with no explicit initial region discovered home us-chicago-1 and assessed ap-melbourne-1, confirming home connection and scan scope are distinct. No GPU nodes were allocated. Both RMS packages are rebuilt from the committed source.

## Assessment-only discovery and direct JSON handoff
- [x] Remove image/version/platform/feature controls from discovery; assess published image platforms and optional feature definitions automatically.
- [x] Emit one deployment_inputs JSON object with the model, assessment choices and frozen recipe/image evidence.
- [x] Accept that object directly in deployment with a selection ID and target infrastructure; apply image/feature/argv/environment overrides only there.
- [x] Test direct handoff, platform/channel choices, explicit expert settings and backward-compatible deployment inputs; validate/package/document the revised flow.

Direct handoff pre-cloud verification: ten resolver tests, seven discovery-root tests, twelve deployment-root tests and nine selected manifest/schema checks passed. Deployment tests cover the same JSON via object and RMS literal-text input, no repeated model/workload values, assessed nightly selection, unavailable channels and wrong CPU platforms. Documentation now presents deployment_inputs as the primary single-piece handoff; the old selection script is optional legacy support.

Final handoff verification: 24 script/render checks and 54 native Terraform tests passed (resolver 10, planner 16, profile 9, discovery 7, deployment 12). A live RMS Plan for Qwen/Qwen3.8-27B succeeded across 16 READY regions, using home us-chicago-1 and stable vLLM 0.33.0 platform digests. It preserves 56 expert hardware options with unknown memory/GPU quantities and zero automatic candidates: the composite/multimodal estimator and deployment modality contract remain unsupported. The single output is retained privately at work/deployment-inputs.tfvars.json; its source plan is work/handoff-rms-plan.json. Synthetic direct-handoff Terraform tests pass; this model was not deployed or runtime-tested. The live fixes cover a literal region template, blank scope entries and uncatalogued GPU image selection. Both RMS ZIPs passed archive integrity checks. No GPUs were allocated.

## Recipe JSON hardware suggestions
- [x] Consume hardware/variant-specific JSON renderings, image digests and default parser settings; reject adjusted identities.
- [x] Generate ranked single-node suggestions with workload-aware heuristic budgets, retain raw hardware evidence and explicit untested status.
- [x] Carry each selected suggestion unchanged into deployment and guard changes to workload/topology; expose compact recommendations.
- [x] Preserve optional cache/companion plans and separate config/tokenizer metadata without executing installation commands.
- [x] Verify Qwen RMS discovery and actual JSON handoff with mocked cloud deployment; test Flint BF16 adaptation and NVFP4 requirements.

New-path verification: final Qwen RMS Plan succeeded, returning 22 suggestions and four cache plans across 16 READY regions. Local checks cover 24 planner, 10 profile, 14 deployment-root and seven discovery-root tests, one real-JSON mock integration and 24 script/render checks. GPU runtime validation and benchmarking remain not run. Multi-node suggestion inference, full multimodal tests, cache companion deployment and automatic external-config staging remain future work, explicitly identified in the handoff/documentation.

## Confirmed capacity choices
- [x] Trace incomplete/zero capacity and entitlement observations; distinguish diagnostics from selectable deployment options.
- [x] Require AVAILABLE reports and enough instances, positive applicable limits and quantity-specific GPU headroom for every selectable option. Charge entitlement for the full OCI host, not just TP GPUs.
- [x] Preserve excluded rows and reasons in diagnostics; make the selectable availability result explicitly available-at-scan.
- [x] Test zero, missing/unknown, insufficient quantity, unknown quota units and successful observations; verify against saved live scan, package and commit.

Confirmed-capacity verification: 32 planner tests, seven discovery-root tests and 14 deployment-root tests passed. A native Terraform replay of the actual saved Qwen/API observations returned nine selectable suggestions, all available_at_scan with sufficient whole-host GPU entitlement; all thirteen zero-capacity suggestions were excluded. The replay handoff explicitly records that it is not a new capacity query.

## Root-level RMS packages and CI artifacts
- [x] Flatten each stack's Terraform files/schema/provider lock to ZIP root, place modules in modules/, and relocate packaged local module/asset paths without changing repository development layout.
- [x] Verify both extracted packages with Terraform init/validate from the root and reject missing assets or leaked state/tests/private files.
- [x] Add a main-push GitHub Actions workflow that builds, validates and uploads the two stack ZIP artifacts.
- [x] Update packaging/RMS instructions, build final ZIPs, commit and integrate after local verification. GitHub-hosted execution awaits a remote push/merge.

## Module-owned assets and workspace cleanup
- [x] Trace runtime/build references; remove model/engine catalogs and retain only GPU metadata and deployment infrastructure defaults.
- [x] Move runtime scripts/data into owning modules; encapsulate cross-region OCI CLI discovery in a module and move developer tests to tests/.
- [x] Simplify ZIP packaging to module-local assets and exclude build tooling from deployment archives; update tools/docs/tests.
- [x] Validate modules, scripts, JSON handoff and extracted packages; clean obsolete caches/research copies while preserving state, inputs and current handoff evidence.

## Live-only model/engine lookup (scope update)
- [x] Remove static model/engine catalogs, dropdown compatibility input, catalog policy/generator and selection helper.
- [x] Resolve recipe source owner/path/SHA from the live per-model API and select alias variants from its recommended variant metadata.
- [x] Keep GPU specifications and deployment infrastructure pins module-owned; no serving engine fallback catalog remains.
- [x] Revalidate native/runtime/package flows and finish temporary workspace cleanup before integration.

Module-owned/live-only verification: 19 script/render/schema checks and native model-profile (10), recipe resolution (10), planner (32), discovery-root (6), deployment-root (14) checks passed. Both delivered root-level ZIPs passed extraction/init/validate. A real RMS Plan with module-owned OCI discovery and live recipe source metadata succeeded; its handoff also passed mocked deployment planning without catalogs. Latest private evidence is work/latest-discovery-plan.json and work/deployment-inputs.tfvars.json. No GPU allocation or inference occurred. GitHub workflow execution remains pending a remote push/merge to main.

Cleanup removed the clean production-stack research clone, unused OCI 7.32.0 cache, duplicate Helm cache, obsolete SDK/CLI intermediate reports and logs. Active provider caches/symlink targets, 18 Terraform state files, input tfvars, research notes and current handoff were preserved. work/ was reduced from about 621 MiB to 326 MiB; remaining size is mostly active providers. tools/ was empty and removed.

## Reuse OKE GPU/network add-ons
- [x] Remove application-owned GPU Operator/RDMA plugin installation and pins; retain OKE ownership.
- [x] Record existing enhanced-cluster add-ons and versions through native OCI data sources.
- [x] Validate node GPU/RDMA resource availability, resolve the advertised RDMA resource name, and render requests against it without guessing a service version upgrade.
- [x] Test missing/ambiguous resources, managed names, rendering, inventory and packaging; document prerequisites and runtime validation boundaries; commit the feature.
- [ ] Validate on live OKE GPU nodes before integrating into main, following the branch validation workflow.

Local verification passed: 24 script/render checks (including the released Helm chart), 10 allocation tests, 14 deployment-root tests and both extracted RMS ZIP validations. The feature is committed on `feature/reuse-oke-addons`. GPU allocation, actual inference and RDMA fabric validation were not run for this change.

## Deployment defaults, read-only preview and RMS handoff

Design: use RMS's stack compartment and dynamic cluster picker. A read-only target module resolves the cluster's VCN, existing worker/pod subnets and OKE-supported images for the exact Kubernetes version, OS and shape. Unambiguous existing subnets are reused; ambiguous choices remain explicit advanced overrides. Sharing a VCN does not prove API security/routing. Default to preview mode: no OCI allocation or DevOps resources. CPU sizing is an explicit component-budget estimate carried by discovery, not a model-weight heuristic. Keep image/network overrides hidden behind advanced settings. GPU driver/container CUDA compatibility remains pending until actual GPU runtime validation; image metadata must not be presented as that proof.

RMS limits each input variable to 8192 bytes. Retain the full report for audit/local workflows, emit a compact frozen handoff per selection with a measured inline budget, and support authenticated Object Storage input for larger reports. Never silently truncate launch arguments or model/image provenance.

1. [x] Generate compact per-selection handoffs, byte limits and authenticated large-payload input; verify the existing report and oversize/Unicode cases.
2. [x] Implement native image/cluster/network target discovery and CPU sizing; verify exact-version/shape filtering, overrides, ambiguous subnets and VCN mismatch.
3. [x] Default deployment to a read-only preview, simplify RMS controls and use derived values downstream; verify no OCI managed resources are planned in preview.
4. [x] Document the minimal workflow, CUDA/RDMA boundaries and artifacts; run native/render/package checks, commit the feature. No live allocations, deletions or DevOps executions during this work.

Verification: all 13 configurations in the saved report export as RMS-safe inline JSON (maximum 7966 UTF-8 bytes, retaining capacity timestamps). Tests passed: 27 script/render and 92 native checks, including the actual saved report through a compact handoff to a mocked no-allocation deployment preview. A real OCI image selection confirmed the OKE/version/shape combination without creating managed resources. Docker manifest metadata was reachable, but the live config-blob redirect encountered a local CDN certificate trust failure; TLS was not disabled. Registry metadata is optional in preview and required before provisioning; driver/kernel checks still need real GPU nodes. Runtime execution and RMS form validation remain pending a selected cluster.

Both committed-source RMS packages were extracted, initialized and Terraform-validated successfully. The normal form uses the stack compartment and a dynamic cluster picker; optional network/image/RDMA tuning is hidden. The benchmark pipeline exposes numeric per-run parameters. Implementation is committed on feature/deployment-defaults-preview; no OCI allocation, scale-down, deletion or DevOps deployment was executed. Live cluster/RMS-form/GPU validation remains a separate follow-up before main integration.

## Proposed replacement: generated deployment bundles

The user reports that the inline inputs still do not work in RMS. Prefer a deployment ZIP per confirmed option, with frozen data loaded from a bundled file, published to private Object Storage with an expiring object-read PAR and a region-specific RMS create-stack URL. This replaces the intended inline handoff, not the assessment or deployment infrastructure modules. The researched design and phased checklist are in [generated-deployment-bundles.md](../docs/generated-deployment-bundles.md). Implementation is not started; no bucket, PAR, RMS stack or compute resource has been created for this proposal.

Design refinement: folders are fixed at model/region/shape, with bundle kind, UTC timestamp, run ID and option ID only in ZIP filenames. A refresh publishes a new version but does not automatically update existing deployment stacks. Generate the actual schema from a template, with matching Terraform declaration defaults from the same recommendation map. Bundle only the selected layer specification/provenance, not the full multi-option report. Local Terraform checks confirmed that environment value 2 overrides generated default 4 and that the original validation still rejects 0. The effective-value resolver must honor overrides and invalidate stale sizing evidence; schema changes alone are insufficient. Authenticated RMS form testing remains pending.

## Proposed lifecycle split

The latest design has three independent stack types: discovery, a reusable infrastructure/platform owner, and per-model deployments. Infrastructure owns retained pools, managed add-ons/shared CRDs/controllers and the shared DevOps project/foundation. Model stacks reference that project/pool and own model workloads plus per-model deploy/validate/benchmark/retire pipelines. Use a versioned platform descriptor/readiness contract rather than a full infrastructure state dump. New-allocation eligibility and existing-pool suitability are separate: zero spare OCI capacity must not hide a usable retained pool. See [platform-model-lifecycles.md](../docs/platform-model-lifecycles.md) for ownership, flow, refactoring phases and tests. Current source is still the combined deployment implementation; the split is a proposal, not a completed feature.

## Deferred model undeploy pipeline

Use an independently invoked OCI DevOps Shell pipeline, following the shell-stage pattern in [oke-langfuse](https://github.com/streamnsight/oke-langfuse/tree/main/modules/devops/deployment_stages/shell_stage). Deleting pipeline records does not reverse shell commands. The user has prioritized node pools and shared CRDs first; model/undeploy implementation is deferred.

1. [ ] Add the undeploy pipeline, bundled cleanup script, namespace-scoped RBAC and model ownership labels. Verify it is separate from deploy/validate/benchmark and has no automatic trigger.
2. [ ] Remove only the model Helm release, owned LWS instances/services and temporary test resources; handle absent releases, partial deployments, old replica counts and unavailable GPUs. Invalidate validation evidence and wait for model pods to disappear; surface cleanup errors. Preserve hosts, shared controllers, namespace/RBAC and data according to Helm retention policies.
3. [ ] Exercise retry/partial failure/ownership boundaries with local command mocks, native Terraform tests and packaged-stack validation. Document operator sequencing and limitations, commit the feature, and retain live OKE validation as pending. No live undeploy, node changes or pipeline executions.

## Infrastructure-first implementation

Scope: an independent infrastructure state with a stable platform name, selected region/AD/shape/host count and existing cluster. Create GPU infrastructure only; use existing CPU pools for controllers. Model-local cache colocation belongs to the later model phase. No model ID, serving image, recipe, benchmark or large discovery JSON is required. Reuse the allocation/target modules, including retained-pool protections. One platform owner per cluster in this first pass. Default to read-only preview; do not create, resize, cycle or delete GPU hosts during verification.

1. [x] Add an infrastructure root with RMS dynamic cluster/compartment inputs, native GPU image/network resolution, hardware/RDMA checks and a detailed GPU-only pool/bootstrap preview. Test preview has no managed OCI resources, CPU image lookup/pool creation or model dependency.
2. [x] Add a platform DevOps Shell bootstrap pipeline, shared project/evidence storage and explicit administrator RBAC bootstrap. Check actual GPU/CPU resources, reuse OKE GPU/network add-ons and install or reuse a compatible LeaderWorkerSet controller/CRD. Existing controllers must not be silently adopted/upgraded. Prometheus/KEDA remain outside this first validation pass.
3. [x] Publish a small platform descriptor with stable pool/project references and a generation-specific readiness object written only by the pipeline. Terraform apply must not automatically start bootstrap or advertise runtime readiness.
4. [x] Package the infrastructure root with root-level main.tf/schema.yaml, add CI artifact publication and operator instructions. Validate native tests, mocked bootstrap execution and extracted archives; preserve user files and remove temporary dependencies.
5. [ ] Validate authenticated RMS preview and platform bootstrap on an explicitly selected target. Allocation/runtime GPU and RDMA fabric validation remain pending; no live provisioning is authorized in this pass.

Infrastructure verification: 52 native Terraform checks passed (allocation 11, target lookup 10, bootstrap 1, infrastructure root 8, earlier deployment root 22). Script/schema/render checks passed 35, with one optional production-stack chart check skipped; the released LWS 1.0.0 chart was rendered and checked, and all seven complete bootstrap/readiness fixtures passed. Discovery, infrastructure and combined deployment ZIPs were extracted, initialized and Terraform-validated at their root. A transient registry/provider download failure on the final ZIP was resolved using the installed provider cache. The infrastructure artifact is `work/packages/oke-llm-infrastructure.zip`. Temporary Node dependencies and reference/chart copies were removed; user-staged AGENTS.md and existing state/inputs were preserved. No GPU allocation, resize, deletion, DevOps execution or live OKE admission test occurred. Keep the feature branch pending live validation; per-option bundle publishing and model/undeploy work remain deferred.

## Discovery-root repository layout

Make the source tree mirror the entry ZIP: root discovery Terraform/schema, reusable modules/, and child roots under templates/infrastructure and templates/deployment. The latter remains explicitly the older combined implementation, not a completed model-only stack. Keep independent Terraform states and standalone developer build targets. Embed both child roots in the discovery package and publish only that entry ZIP from CI. Template embedding does not implement per-option generation/publication.

1. [x] Move discovery to the repository root, reusable modules/examples to root directories, and downstream roots under templates/. Preserve local state, tfvars, caches and private outputs; verify state/input file bytes are unchanged.
2. [x] Update module sources, development tests, CI test discovery, package construction and single-artifact publication. Keep child Terraform files out of the entry root and validate each embedded child from its own directory. Exclude development/private files from every layer.
3. [x] Update current instructions and path references; run moved native suites, script/schema checks and extracted ZIP validation. Commit without the user's staged AGENTS.md. No cloud provisioning, pipeline runs or node changes.

Layout verification: all 16 native suites passed (139 assertions); script/schema checks passed 35 with two optional local-chart checks skipped. The discovery ZIP and both embedded roots initialized and validated independently. State, backup and tfvars SHA256 hashes were unchanged; four local cache symlinks were repaired after the move. Automatic option rendering, Object Storage and PAR publication remain a separate implementation phase below.

## Infrastructure option publisher

Publish configured infrastructure ZIPs only for confirmed options. Use native archive resources at Apply, native OCI bucket/object/PAR resources, generated editable schema/HCL defaults and a bundled selected specification. No scripts run Terraform and no cloud resources are allocated during local verification. The legacy combined deployment is embedded for development but is not published as a model-only stack.

1. [x] Add Apply-time infrastructure template rendering, selected specification/manifest, safe dependency closure and matching editable schema/HCL defaults. Guard the deployment region against the bundled recommendation and disclose expert edits.
2. [x] Add private artifact storage, object-read PARs with expiry, fixed model/region/shape folders and timestamp/run/option IDs in ZIP filenames. Discovery outputs launch links; refreshing artifacts does not own GPU infrastructure. Document replacement/expiry semantics.
3. [x] Wire confirmed discovery choices and RMS publication settings; test empty/excluded choices, generated ZIP contents/defaults, wrong-region guards, native archive creation and separate saved Plan/Apply filesystems with OCI mocked.
4. [x] Repackage and validate the entry and generated child roots. Record actual versus mocked evidence; commit without running OCI allocation or DevOps pipelines. Live authenticated upload/PAR/RMS form validation remains pending.

Publisher verification: four publisher runs passed using the real archive provider 2.8.1 and mocked OCI, including an input file over 8192 bytes; root discovery passed eight runs including publication filtering/disablement. Three tests against an extracted actual child ZIP passed (default preview, expert override, wrong region), and an archive-only saved Plan applied successfully from a fresh directory. The infrastructure template's eight baseline runs still pass. Script/schema tests passed 35 with two optional chart checks skipped. Combined with unchanged suites validated during relocation, this covers 145 native runs plus three generated-child checks. The entry ZIP and both embedded roots passed extraction/init/validate. Template/provenance paths and private state/tfvars byte checks remain intact. No live Object Storage, PAR, RMS stack, GPU or DevOps resources were created. Refresh rotates the published set and may revoke older links; append-only retention is not implemented. Model-only publication remains deferred.

## Live RMS launch import correction

1. [x] Reproduce the reported Frankfurt GetPackage failure without creating a stack. Check the existing PAR over both its native customer endpoint and the documented classic Object Storage endpoint; validate ZIP integrity and identical bytes.
2. [x] Normalize the new commercial customer endpoint only for RMS links, preserving the PAR path and artifact region. Keep existing classic/noncommercial endpoints unchanged. Clarify the recommended button versus all available choices.
3. [x] Add endpoint regression coverage, validate affected native/schema/package checks and browser import through variable configuration. Preserve staged AGENTS.md and state; do not create stacks or allocate/modify GPU hosts. Record any remaining live validation limits.

Live correction verified: both endpoints returned the same 34,519-byte ZIP, which passed CRC and Terraform validation. The user confirmed the classic link works, and its actual Configure variables form was inspected with the expected Frankfurt AD-2/A10/one-host/204 GiB fields. Six publisher and eight discovery runs passed, as did 35 script/schema checks (two optional chart skips) and extracted-root package validation. No stack creation, GPU allocation, Object Storage change or PAR rotation was performed. Source change is committed on fix/rms-launch-endpoints; only model/node runtime validation remains outside this import fix.

## RMS form tag and empty-list defaults

1. [x] Inspect the reported invalid tag in the live wizard. Console-generated ZipOrigin has a 288-character value, above OCI's 256-character limit; no ZipOrigin tag exists in our Terraform. Clear its key/value in the pending form and confirm Review has no Tags section. Do not submit Create.
2. [x] Normalize blank/whitespace/null NSG list entries to inherited networking, preserving actual IDs. RMS creates an empty list row that serializes as [""], even after removing the last row. Ten infrastructure tests and three corrected Frankfurt ZIP preview/override/region tests passed, including RMS placeholder inputs.
3. [x] Document the Console-specific tag cleanup in the guide/schema, retain provenance in the manifest, and render a corrected prefilled Frankfurt ZIP with OCI mocked. ZIP CRC and extracted Terraform validation passed; 35 script/schema checks passed (two optional chart skips). Preserve user form choices and leave final stack creation to the user. The old live wizard still references its original immutable ZIP.

Corrected local bundle: work/packages/oke-llm-infrastructure-frankfurt-fixed.zip. No discovery refresh, capacity reservation or cloud mutation was performed. The tag-free Review screenshot is work/validation/frankfurt-rms-tag-free-review.jpg. Entry-package validation is repeated after committing the source so its embedded template includes the fix.

## Durable RMS origin-tag compatibility

1. [x] Inspect the newly launched wizard. It recreated ZipOrigin from its 285-character package URL and failed with Invalid tags; clearing the earlier wizard did not prevent this. Clear the current unsaved form without submitting Create.
2. [x] Keep the descriptive model/region/shape archive, publish an identical short-path launch copy, and scope the existing ObjectRead PAR to that copy. Enforce the 256-character limit on the final decoded package URL. No new user inputs or cloud writes during development.
3. [x] Test real-length PAR tokens, long model IDs, unchanged archive contents and rejection of overlength package URLs. Validate extracted ZIPs and packaging, document the residual Console-added tag accurately, and commit without the user's staged AGENTS.md.

Eight publisher runs and eight root discovery runs passed with OCI mocked. The actual generated child ZIP passed extraction, Terraform validation, three preview/override/region tests and saved-Plan/fresh-Apply archive verification. The entry package and both embedded template roots passed extraction/init/validate. State, backup and tfvars hashes and the user's staged AGENTS.md were preserved. No cloud artifact was republished; existing URLs remain unchanged, and live validation of a newly published short link remains pending.

## IMDSv2-only node launch defaults

1. [x] Verify Oracle's existing-pool update interface. OKE reserves node_metadata.areLegacyImdsEndpointsDisabled = "true" to disable IMDSv1 on future nodes; the tenancy's IMDSv1 restriction is not a tag.
2. [x] Set the documented string metadata value on GPU pools and the shared module's optional CPU pool. Assert both launch configurations comply with IMDSv2-only tenancies; retain preview/allocation safeguards.
3. [x] Document a metadata-preserving CLI update for the existing CPU pool and the distinction from editing individual Compute instances. Validate/package the source change without updating live pools, cycling nodes or triggering pending CPU launches.

All 11 allocation test runs passed with OCI mocked, including both metadata defaults. Infrastructure and combined deployment roots passed Terraform validation. The entry package is rebuilt from the feature commit and checked for ZIP integrity and both node-pool defaults. Real Terraform state, backup and tfvars hashes and staged AGENTS.md are preserved. No live node-pool update was executed; the external CPU pool requires its owner to apply the documented change.

## GPU-only debug gate and live CPU platform bootstrap

1. [x] Replace the infrastructure-wide provision flag with temporary skip_gpu_allocation (normal default false). Always create platform resources on Apply, propagate the debug choice through discovery/publisher/schema/packages, and expose RMS outputs. Do not allocate GPUs during this validation.
2. [x] Run bootstrap with CPU-only readiness when debugging. Keep normal GPU/RDMA checks, generation evidence and controller ownership safeguards. Record skipped GPU validation explicitly; never report model readiness.
3. [x] Test both modes and generated ZIP defaults, validate/package source, and update the existing RMS stack in debug mode. Inspect a saved plan to confirm no GPU node pools, Compute Clusters or capacity reservations before Apply.
4. [ ] Provision platform resources, establish the narrowly scoped pipeline's cluster authorization, run the DevOps pipeline, verify LWS CRD/controller/admission and persisted evidence, and record exact live limitations. Preserve staged AGENTS.md and existing GPU allocations.

Local checks passed: 10 infrastructure runs, nine publisher runs, nine discovery runs, one platform-module run, four extracted-child runs and a saved-Plan/fresh-Apply archive check; 38 script/schema tests passed with two optional chart skips. The released LWS chart was fetched and its version is v1.0.0; controller reuse now accepts its v-prefixed chart spelling without upgrading. The user's OBC kubeconfig context is used for the test cluster, without changing the global current context.

The live saved Plan contained 11 platform creates, one local specification update, no deletes and zero GPU/node/Compute Cluster/reservation resources. Apply created the nine regional platform resources, then IAM rejected dynamic-group creation outside the home region (ORD). The correction discovers the home region via native tenancy/region data and routes only IAM resources through the home provider. An OBC transport check also identified missing egress from the bastion/API subnet to the private API on TCP 6443; a single-host rule is prepared, awaiting the user's approval. No network rule was changed.
