<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Discovery recommendations and memory transparency

## Outcome

Put deployment actions before technical serving configuration. Explain and improve recommendations using observable hardware fit and confirmed growth headroom, rather than treating GPU count as a performance/cost metric. Hide zero-host regional capacity rows while keeping positive supply with zero/insufficient entitlement. Show known memory components and the planner's actual heuristic budget without claiming a complete hybrid/multimodal runtime estimate.

User preference confirmed: hardware suitability first, then growth capacity.

## Phases

1. [x] Update the report order/filter and add regression checks for deployment actions before serving details, positive-capacity limit-review rows, and hidden zero/unknown-only rows.
2. [x] Rank eligible suggestions/candidates by GPU memory per device, smaller per-replica GPU/host sharding, RDMA capability for otherwise equal fit, and quantity-confirmed AD growth; use exact-shape regional physical supply and allocation size as later tie-breakers. Expose factors and recommendation rationale in JSON/HTML. Count complete model allocations, cap AD growth by both physical hosts and entitlement, and never add shared entitlement ceilings across ADs or promise future reservations. This is a transparent fit heuristic, not a throughput or price prediction. Keep eligibility unchanged.
3. [x] Decouple resident-weight metadata from unsupported complete estimates. Expose Qwen hybrid full-attention KV payload separately from unknown recurrent/vision allocations. Expose the existing planner formula and budget components (including the deliberately all-layer full-attention KV surrogate and per-GPU runtime allowance); do not silently promote the heuristic to a validated complete estimate. No new discovery scans or HTTP lookups.
4. [ ] Run focused Terraform/report regressions, replay the saved Qwen observation, inspect desktop/mobile HTML in a browser, validate the packaged roots, document results, commit and integrate after validation. Preserve user AGENTS.md staging, the separate untracked discovery review and all original state/tfvars. Do not allocate/change GPUs or execute pipelines.

## Evidence and edge cases

- Qwen/Qwen3.8-27B's pinned config contains 64 text layers: 16 full attention and 48 linear attention, plus a vision encoder. Published BF16 counts support a weight estimate even though cache-manager padding, recurrent cache policy and vision workspace remain unprofiled.
- vLLM's hybrid cache manager pads/groups different state types and can cache recurrent state at block boundaries. A token KV formula alone is not its total allocation: https://docs.vllm.ai/en/latest/design/hybrid_kv_cache_manager/ . State shape implementation: https://github.com/vllm-project/vllm/blob/main/vllm/model_executor/layers/mamba/mamba_utils.py .
- Larger VRAM can reduce sharding but does not prove higher throughput. GPU memory bandwidth, NVLink/NVSwitch inside hosts and RDMA between hosts have distinct effects: https://docs.vllm.ai/en/latest/serving/parallelism_scaling/ . Catalog capability does not reserve an RDMA fabric or enable it in a single-node plan.
- Unknown and conflicting capacity are never positive supply. Raw diagnostics retain exclusions, including zero hosts, without cluttering the main capacity table.

## Validation so far

- Model profile: 15 mocked runs passed, including the pinned Qwen hybrid dimensions and independently known weights.
- Planner: 52 mocked runs passed, including A100 over A10, growth limited by entitlement, equivalent-GPU RDMA preference and TP4/TP2 replica packing under the same 71.83 GB budget.
- Report: 13 Terraform runs and 8 JavaScript tests passed; root discovery/publication: 11 runs passed.
- Saved real Qwen discovery replay passed with all HTTP data mocked and no OCI scan. It retained three confirmed choices and reproduced 55.56 GB weights, 1.07 GB partial full-attention KV, the 4.29 GB all-layer sizing surrogate and the unchanged 71.83 GB payload budget.
- Browser verified action ordering, the expanded sizing formula, no errors/warnings and 390-pixel layout without horizontal overflow. Preview HTML and screenshot are private under `work/recommendations-validation/`. The preview uses saved capacity/publication links, not a new assessment.
- Native package validation, cleanup and integration follow below. No GPUs or DevOps resources were changed or executed.
