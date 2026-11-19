<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->

# Serving-layout quantity assessment

## Phase 1 — contract and failure cases

- [x] Reuse model/recipe compatibility separately from capacity and entitlement.
- [x] Preserve existing aggregated allocations; derive P/D role counts without new scans or ZIPs.
- [x] Account for complete weights in each role, whole-host packing, minimum decode replicas and one prefill instance.
- [x] Keep unknown capacity/quota, insufficient quantity, foreign ADs and incompatible cache/topology unavailable with reasons.

## Phase 2 — implementation and verification

- [x] Add the pure `modules/discovery/serving-layouts` module and typed scalar launch overrides.
- [x] Run focused Terraform regressions covering geometry, model/recipe gates and quantity/scope failures.
- [x] Validate Terraform 1.5.7 configuration compatibility and prepare the isolated module for integration.

This module indexes shape observations by exact region/AD/shape, then evaluates each existing option. Scope lookup is O(options + observations); duplicate-scoped observations remain separate evidence and conflicting quota quantities stay unknown. It does no cloud calls, provisioning or per-model runtime certification. Report rendering, quick-create links and integration are owned by the parent feature.

Validation: 24 focused Terraform 1.9.8 regressions pass through `scripts/test-terraform.sh`, using the repository's strict fake OCI CLI. No providers or cloud calls are needed. Terraform 1.5.7 init/validate also passes. Tests include TP2 roles sharing four GPUs, TP4 requiring two hosts, preserving minimum decode counts with spare-slot packing, positive/unknown/insufficient physical and quota quantities, exact-AD matching, missing/fault-domain scope, model/recipe exclusions and positive eligibility for uniform-attention MoE. These checks validate metadata planning, not runtime transfer or performance.
