<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Multi-host deployment options and concise quota summaries

## Design

Extend the existing recipe-adaptation path rather than implement another deployment mechanism. Enumerate intra-host TP and cross-host PP with the existing maximum-host bound. Keep one host group per model replica and use the existing LeaderWorkerSet/mp deployment contract. Check upstream architecture PP support from immutable source evidence; keep image/runtime association uncertainty visible. Retain exact dtype, platform, capacity and quantity-specific entitlement gates. A10 cross-host PP uses Ethernet, with no RDMA/performance promise.

Use component-aware per-rank bounds: account for the largest PP layer partition, KV-head replication under TP, persistent/unsharded embedding overhead, per-device runtime and proportional uncertainty. A heuristic result stays explicitly estimated and requires runtime validation. Missing dimensions or PP support evidence exclude the executable suggestion without erasing sizing diagnostics. Keep capacity/quota scoped to one AD and reserve all hosts for all replicas. Prefer a fitting single host; enumerate the smallest fitting PP per TP rather than flooding the report with larger equivalent configurations.

Reuse deduplicated single-host recipe arguments/image metadata as the adaptation baseline. Do not trust a multi-node API request that silently falls back to single-node; the live API was observed doing this. Multi-host topology is owned by our existing deployment flags, while source evidence establishes PP capability. Do not enable speculative/disaggregated, the currently single-host-only LMCache adapter, or other coupled distributed features implicitly.

Search cost is O(observed region/AD/shape rows x four TP choices x maximum PP), bounded by the existing 32-host validation limit. One native HTTP read supplies the pinned supported-model table; no per-host recipe requests or new runtime dependency.

## Phases

1. [x] Inspect discovery/deployment topology contracts and upstream capability evidence; verify the existing backend supports LWS/mp host groups. Check the current workspace and create a feature branch here, without another worktree.
2. [x] Add executable regressions for two-host sizing, uneven PP partitions, KV replication, dtype/platform/PP exclusions, complete replica capacity/quota, and the previously working one-host case. Implement enumeration, evidence and emitted topology while retaining manual/runtime validation.
3. [x] Remove the repeated selected AD from option-card limit/headroom summaries; preserve regional/global scope and full scope details in the expanded body. Verify desktop/mobile rendering and multi-host planned commands.
4. [x] Run focused source and downstream rendering/target regressions, Terraform 1.5.7 archive checks, commit/merge and rebuild. Refresh discovery through a reviewed publication-only live Plan/Apply. Do not provision/recycle GPUs or execute model pipelines to test this metadata feature.

## Validation record

Source checks: planner 77 passed; root Terraform 15 passed (including pinned Qwen short/long-context replay); model-delivery Terraform 45 passed; model-target Terraform 17 passed; report JS 18 passed. Rendering and delivery JS: 42 passed, one optional external-router fixture skipped. Browser at 1200px and 390px verifies the seven-host TP4/PP7 option, full planned command, no horizontal page overflow, concise collapsed quota and retained expanded AD scope.

Release `a9b4437` discovery archive passed Terraform 1.5.7 init/validate at the entry root and both embedded template roots. All eight actual RMS-generated infrastructure/model ZIPs were downloaded and passed Terraform 1.5.7 init/validate; model defaults match PP/host-group counts and infrastructure defaults enable LWS. Pinned upstream metadata contains unrelated plugin tables; regressions ensure only each table's own PP column can establish support.

Live RMS Plan `ocid1.ormjob.oc1.us-chicago-1.amaaaaaafigrwqyauib5strwrrpqcb42u2ejiyprxwz5435elov4sjhfblsq` succeeded. Its managed changes were restricted to archives, publication metadata, Object Storage objects and read links. Apply `ocid1.ormjob.oc1.us-chicago-1.amaaaaaafigrwqyaxk26vug2kwzrs4445h2rgmaaqvuwvheihkbg2uacakda` succeeded. All live input variables were preserved (saved Qwen27B workload was 262144 x 4). The report now publishes four options: A10.4 TP4/PP7 in Melbourne and Montreal; B4.8 TP8/PP3 and TP4/PP4 in Osaka. Montreal shows 56 GPUs configured / 52 GPUs remaining without repeating the AD in those summaries. The actual published report was inspected in Chrome.

The earlier parser-only Plan was never applied; a superseded second Plan was cancelled before publication. Source code, metadata flow and generated artifacts are validated; no GPUs were provisioned or model pipelines executed. Seven A10.4 hosts are an estimated long-context fit, not a measured runtime result. The independent 4096 x 4 replay continues to choose a single TP4 A10.4 host.

Integration uses a fast-forward into main and an entry-ZIP rebuild from committed main. The live upload is functional commit `a9b4437`; this final validation record is documentation only. Static source support and metadata tests are distinct from GPU/runtime validation. Preserve saved state, inputs and logs outside packages; never clear live allocation/coordination locks for testing.
