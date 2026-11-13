<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Project status

CPU platform bootstrap is now validated live on the existing Frankfurt OKE cluster. The infrastructure stack creates DevOps, logging, private platform storage and scoped IAM resources even when GPU allocation is skipped. Two pipeline deployments succeeded: the first installed LWS 1.0.0 and the second reused the same release at revision 1. CRD establishment, controller rollout and server-side admission passed. No GPU resources or existing network rules were changed. See [the live validation report](cpu-platform-validation-2026-11-13.md).

The temporary `skip_gpu_allocation` switch replaces the infrastructure-wide provision flag. Its normal default is false: infrastructure Apply allocates GPU hosts and creates the platform. For current debugging, the existing RMS stack has it set to true; the pipeline still installs CPU controllers and records `validation_scope=cpu_components_only` and `gpu_validation=skipped_debug`. Terraform Plan is the preview mechanism. Never enable skipping after allocating retained GPU hosts.

Discovery is the repository root, reusable modules live under modules/, and downstream roots live under templates/. CI packages one discovery entry ZIP containing the templates. Discovery accepts a Hugging Face model, context/concurrency, reads structured model and live vLLM recipe data, scans subscribed regions and publishes configured infrastructure bundles only for confirmed capacity/headroom choices. Model/image/configuration validation remains distinct from capacity eligibility.

Generated infrastructure ZIPs contain editable schema/HCL declaration defaults, a selected specification file, a region guard and template provenance. Large discovery data is not passed through an RMS variable. The debug choice is propagated through discovery, the publisher and packaging. Short launch copies avoid overlength Console ZipOrigin tags while descriptive archives remain browsable; these latest publication changes have local native/mocked coverage and have not been republished to the discovery bucket during this CPU bootstrap task.

The new infrastructure template reuses existing CPU pools and OKE GPU/network support. Bootstrap IAM writes use the dynamically discovered tenancy home region; the regional DevOps/storage resources remain in the deployment region. The current stack has eleven OCI platform resources plus a local Terraform specification record, and zero GPU allocation resources. Application Information outputs were verified in the Console. Pipeline readiness is written separately from Terraform state and remains generation-specific.

The entry artifact is work/packages/oke-llm-discovery.zip. The configured deployed debug artifact is work/packages/oke-llm-infrastructure-frankfurt-cpu-debug.zip. Current outputs, raw evidence and the compact verified runtime summary are under work/platform-debug/. The legacy combined deployment template remains for development; a separate model-only deployment/undeploy stack is still deferred.

Local checks cover both allocation modes, generated defaults, wrong-region guards, home-region IAM, complete Shell runner behaviour and controller ownership/reuse. The actual debug ZIP passed five native contract tests. Live validation covers RMS Apply, IAM, Shell execution, private-VCN connectivity, CPU scheduling, LWS rollout/admission and a repeat run without upgrade. The Shell runtime used timestamped evidence folders when its optional deployment-ID environment variable was absent.

Remaining work includes real GPU allocation/inference, driver/CUDA/NCCL/RDMA validation, model deployment/undeploy, benchmarking, cache companions and durable Responses conversation storage. The RDMA allocation module's separate Compute Cluster IAM policy still needs home-region routing before an RDMA rollout; bootstrap IAM is already corrected. Additional platform stacks also need tenancy-unique bootstrap IAM names. No CPU-only readiness result certifies those GPU/model capabilities.
