<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Project status

The repository now separates discovery, infrastructure, cluster add-ons, model deployment and shared delivery modules. Discovery exposes one consolidated result for every confirmed option and avoids duplicate recipe/region/rendering queries. Its comparison HTML is an optional separate page. The entry ZIP includes infrastructure and model templates.

The separate model stack is implemented and its creation flow is validated live: infrastructure published a bound ZIP, its PAR download/checksum/native validation passed, and RMS created four ACTIVE model pipelines in the existing project with one native Helm and five shell stages. GPU allocation stayed disabled; model pipelines and namespace onboarding were not executed. See [the current validation record](model-deployment-validation-2026-11-13.md), [discovery usage](../docs/rms-discovery.md), [model binding](../docs/model-binding.md) and [component responsibilities](../docs/model-layer-components.md).

The CPU component foundation was previously validated live: parallel LWS reuse/Prometheus/KEDA delivery, aggregate readiness and guarded KEDA uninstall/reinstall succeeded, retaining all six KEDA CRDs. See [that validation](native-component-validation-2026-11-13.md). Automatic OKE GPU/network add-on configuration, GPU exporter scraping, live model staging and real inference/benchmark/cache/conversation-state validation remain future work. The baseline below is historical.

## Previous LWS-only baseline

The CPU platform and editable component pipelines are validated live on the existing Frankfurt OKE cluster. The latest LWS deployment and independent validation runs both succeeded, reusing LWS 1.0.0 at Helm revision 1. A per-run version override reached the validator, produced separate evidence and left the original readiness JSON byte-for-byte unchanged. Both runs checked two existing CPU nodes, controller rollout and server-side admission. See [the current validation report](component-pipelines-validation-2026-11-13.md).

The infrastructure stack has nineteen OCI resource instances plus a local Terraform specification record. It owns DevOps, logging, scoped IAM, a private evidence bucket and an immutable Artifact Registry repository. No GPU allocation resources were created. Existing networking and RBAC bindings were not changed.

Scripts are module-owned readable Bash/jq files, uploaded as checksum-versioned generic artifacts and supplied through native command-spec inputArtifacts. Editable pipeline parameters populate env.variables, with explicit exports for child processes. There are no encoded code/configuration payloads inside the commands. The platform bucket holds specification/readiness/diagnostics, never model weights; discovery's separate bucket holds RMS ZIPs. The selected-pool stack no longer passes a global GPU shape list. Classification uses GPU labels/resources and a shape-name fallback; CPU affinity uses validated CPU types. New GPU pools get nvidia.com/gpu=true.

The temporary skip_gpu_allocation switch defaults to false for normal infrastructure Apply. The current RMS stack explicitly sets it to true for CPU debugging; DevOps still deploys and readiness records cpu_components_only with skipped GPU validation. Terraform Plan is the preview mechanism. Do not enable skipping after allocating retained GPU hosts.

Discovery is the repository root, modules live under modules/, and downstream roots under templates/. The entry artifact is work/packages/oke-llm-discovery.zip. Discovery reads structured Hugging Face and live vLLM recipe data, scans subscribed regions and publishes configured infrastructure bundles only for confirmed capacity/headroom choices. Editable generated schema/HCL defaults avoid large RMS JSON inputs. The current CPU task did not refresh capacity or republish discovery PARs. The configured, deployed debug ZIP is work/packages/oke-llm-infrastructure-frankfurt-cpu-debug.zip.

The platform descriptor, readable deployed command specs and raw runtime evidence are private files under work/platform-debug/. The latest summary is component-pipelines-runtime-evidence.json. RMS outputs were verified in the signed-in browser; later Console refreshes and DevOps pages returned blank content. Pipeline parameter behaviour and runtime results were verified through the service API and successful Shell executions.

Local checks passed for environment types/overrides, script integrity, isolated evidence, explicit upgrade ownership/CRD conflicts, GPU labels/resources, native Terraform and generated ZIPs. The released LWS chart rendered with CPU placement. A regression prevents transient cluster metadata changes from deferring the namespace lookup and replacing the evidence bucket. Artifact upload-by-path retains old versions, requiring explicit artifact cleanup when retiring the repository.

Remaining work includes real GPU allocation/inference, CUDA/NCCL/RDMA validation, model deployment/undeploy, benchmarking, cache companions and durable Responses conversation storage. A previous readiness record is an observation; later model deployment must perform fresh validation after component changes. The RDMA allocation module's separate Compute Cluster IAM policy still needs home-region routing before an RDMA rollout. Additional platform stacks need tenancy-unique bootstrap IAM names. Real component version upgrades have local mocked coverage only. The legacy combined model deployment template remains deferred.
