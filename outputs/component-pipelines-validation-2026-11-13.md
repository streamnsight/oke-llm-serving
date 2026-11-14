<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Component pipeline validation — November 13, 2026

The Frankfurt infrastructure stack now has independent LWS deployment and cluster-validation pipelines, editable settings and native Artifact Registry input files. GPU allocation remains disabled for this debug stack. The deployed runtime source is commit 7522307.

## Storage and configuration

Four readable files — bootstrap.sh, config.jq, readiness.jq and lws.sh — are uploaded to a private, immutable Generic Artifact Registry repository. Each version is its source SHA256. All four service-reported upload hashes match the source versions. Both deployed command specs reference those artifact IDs/versions through inputArtifacts and verify their checksums before execution. The former script objects were removed from Object Storage.

Pipeline parameters populate native env.variables and are explicitly exported for Bash/jq child processes. Settings are scalar strings, validated before use; no credentials or full environment dump enter the evidence. The only remaining base64 transport is the OCI API's wrapper for the inline YAML specification. There are no encoded code/configuration payloads in its commands. COMMAND_SPEC artifacts require argument_substitution_mode=NONE.

The private platform bucket holds the desired specification and mutable readiness/per-run diagnostics. It contains no model weights. Discovery uses a different bucket for generated RMS ZIPs. The platform output now includes script_repository_id, component_pipeline_ids.lws and validation_pipeline_id.

## Node placement

The selected-pool specification and pipeline parameters no longer include the full GPU shape list. New GPU pools receive nvidia.com/gpu=true. Classification checks GPU labels, advertised GPU/MIG resources and an OCI shape-name fallback; a missing label alone is insufficient to call a node CPU-only. Controller affinity excludes GPU labels and permits the CPU instance types found during validation. The actual CPU type here is VM.Standard.E5.Flex.

## Live results

The reviewed RMS saved Plan retained the existing bucket and changed no GPU/node/Compute Cluster/reservation resources. Apply succeeded. State contains nineteen OCI resource instances plus the local Terraform specification record, with no GPU allocation resources. Existing cluster networking and RBAC bindings were not changed.

| Check | Result |
| --- | --- |
| LWS pipeline, default settings | SUCCEEDED; existing LWS reused, Helm revision 1 |
| Runtime node/admission checks | Two Ready CPU nodes; rollout and zero-replica server dry run passed |
| Readiness scope | cpu_components_only; GPU validation skipped_debug |
| Validation pipeline with LWS_VERSION=v1.0.0 | SUCCEEDED; override reached the runner; same release/revision reused |
| Original readiness preserved during override | Byte-for-byte identical after the override run |

Default runtime evidence matches the deployed specification generation. The validation override produced the expected separate settings hash, generation and evidence prefix, without changing the original readiness record. Both markers fall within their successful deployment execution intervals and show CPU-only checks, two CPU nodes, rollout/admission success and Helm revision 1. Raw evidence, the verified component-pipelines-runtime-evidence.json summary and the readable deployed command specs are retained privately under work/platform-debug/.

RMS Application Information was verified in the signed-in browser. DevOps Console pages rendered a blank content area through both direct and menu navigation; later RMS refreshes showed the same Console rendering issue. The service API and successful Shell executions validate parameters and runtime effects. A screenshot of the earlier working RMS output view is retained under work/validation/.

## Verification and limits

Forty-six script/schema tests passed, including eighteen bootstrap cases; two optional chart checks were skipped in that suite. The released LWS chart was then fetched and its CPU placement/CRD rendering check passed separately. Native Terraform suites passed for infrastructure (eleven), allocation/labels (eleven) and the platform module (one). The generated debug ZIP passed five native contract tests, and the publisher rendered it using the real archive resource with OCI publication mocked.

No controller version upgrade, GPU allocation, model inference, CUDA/NCCL/RDMA or benchmark was performed. Explicit LWS upgrade/CRD conflict handling has local mocked coverage only. Model deployment/undeploy and additional components remain future work. Artifact upload-by-path retains older versions; repository retirement requires explicit artifact cleanup. The separate RDMA allocation policy still needs home-region routing before a live RDMA rollout.
