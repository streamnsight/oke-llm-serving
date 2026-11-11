# Native discovery validation

Validated November 11, 2026 using Terraform 1.9.8, oracle/oci 7.32.0, hashicorp/http 3.6.3 and the local DEFAULT OCI profile.

## Current implementation

Model inspection uses native HTTP data sources and Terraform expressions. OCI inventory and capacity use native OCI data sources/report resources. Python, Bash analyzers, external-provider wrappers, precomputed-profile inputs and nested Terraform orchestration have been removed.

## Completed checks

- 6 model-profile Terraform test runs passed: exact dense/GQA arithmetic, pinned config URL/provenance, all-expert MoE accounting, over-limit context, missing counts, unsupported dtype and invalid assumptions (some checks share a run).
- 5 native inventory test runs passed: scope separation, shape filtering, unsupported limits, deterministic query budgets/exclusions and unmapped names.
- 5 capacity test runs passed: instance counts, unsupported hardware, known zero capacity, invalid counts and refresh identifiers.
- 2 discovery-root test runs passed: unknown subscribed regions fail coverage validation and only READY subscriptions activate modules.
- Terraform formatting, diff whitespace checks and combined-root configuration validation passed.
- The model-only example completed a live native apply. Qwen/Qwen2.5-0.5B-Instruct resolved to 7ae557604adf67be50417f59c2c2f167def9a775. Its Hub counts produced 988,065,536 weight bytes, 201,326,592 KV bytes for 4096 × four live sequences, and 4,004,250,932 recommended aggregate bytes after the assumed runtime/margin.
- The combined discovery root completed a single live plan/apply across all 16 READY subscribed regions and 26 ADs. This was one Terraform execution/state, with no nested invocation or external interpreter.
- Native plan/apply created 19 reports and 19 Terraform bookkeeping resources. No GPU instances, OKE pools, clusters or DevOps resources were created.
- 1,226 headroom queries completed. Eleven regions' selected entitlement observations are complete; five are partial because their default 100-query budget omitted 98 further checks each. No omitted value is treated as zero.
- Nineteen ADs received complete shape-capacity observations; seven listed no GPU shapes and received no report. See [actual capacity observations](gpu-capacity-scan-2026-11-11.md).

Report refresh/retention is inherited from the capacity module's tested observation-ID lifecycle. Earlier live validation confirmed that the same ID preserves reports and a changed ID replaces report/bookkeeping resources only.

## Evidence and remaining work

Model counts are Hub-published metadata, not independently verified headers. Shape inventory supplies GPU count/RDMA fields but GPU VRAM and NVLink layout still need catalog enrichment. Root entitlement does not prove deployment-compartment eligibility. Capacity snapshots do not reserve hosts, guarantee a launch or demonstrate a feasible RDMA placement.

Tenancy-specific outputs, tfvars, saved plans, state and logs remain ignored in `work/` and Terraform state directories. Reusable modules/examples contain no tenancy credentials or identifiers.

Actual Resource Manager execution and schema-form rendering remain untested. Public-model HTTPS reachability and registry provider installation are required there. Private/gated models and alternate checkpoint selection are not implemented. The deployment/allocation/DevOps stack remains subsequent work.
