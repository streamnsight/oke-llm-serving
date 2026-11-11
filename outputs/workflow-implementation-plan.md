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
- Feature changes are committed on `feature/model-to-deployment-workflow`. The shared checkout's quota branch and unrelated files are preserved. No merge to main or live GPU allocation was performed; end-to-end cloud validation remains pending.
