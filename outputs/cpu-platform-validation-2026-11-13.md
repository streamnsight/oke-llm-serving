<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# CPU platform deployment validation — 2026-11-13

This records the initial bootstrap. The subsequent [component-pipeline revision](component-pipelines-validation-2026-11-13.md) adds Artifact Registry, environment parameters and independent LWS/validation pipelines; use that report for the current resource count and runtime results.

The existing Frankfurt infrastructure RMS stack was updated and applied with `skip_gpu_allocation=true`. It now owns the DevOps foundation while creating no GPU infrastructure. The bootstrap pipeline completed twice: it installed LeaderWorkerSet on the first run and reused the same healthy release on the second.

## Behaviour and packages

`skip_gpu_allocation` is a temporary debug switch, defaulting to false. Discovery passes it into the publisher; generated schema and Terraform declaration defaults agree and remain editable in RMS. Normal infrastructure Apply creates GPU allocation and platform resources. Debug Apply creates platform resources and permits CPU-controller bootstrap without waiting for GPU/RDMA resources. Terraform Plan remains the resource preview mechanism. The former infrastructure-wide `provision_resources` switch was removed from this template; the older combined deployment template is separate.

The discovery entry ZIP contains the updated modules and templates. A configured Frankfurt CPU-debug ZIP was rendered with the real archive provider from the existing model/selection, with OCI publication mocked, and uploaded to the existing RMS stack. Its shape, AD, storage recommendation and selection ID were retained. Discovery capacity was not refreshed and its artifact PARs were not rotated.

## Live evidence

The first saved Plan contained eleven OCI platform creates, one local Terraform specification update and no deletes. It contained no GPU node pools, Compute Clusters, Compute instances or capacity reservations. The first Apply created regional resources but failed because IAM writes require the tenancy home region. The bootstrap provider now discovers that home region natively; the successful retry wrote IAM in Chicago while keeping the platform in Frankfurt. The Shell policy also explicitly includes both container-instance and container permissions.

The final state contains eleven OCI platform resources plus the local specification record, and no GPU allocation. RMS Application Information was checked in the browser and displays the infrastructure preview, platform/project/pipeline descriptor and administrator binding output.

| Check | Result |
| --- | --- |
| Existing node inventory | Two VM.Standard.E5.Flex CPU nodes; zero advertised NVIDIA GPUs |
| First bootstrap deployment | Succeeded; LWS installed |
| Second bootstrap deployment | Succeeded; existing LWS release reused |
| Helm release | lws, namespace lws-system, chart lws-v1.0.0, revision 1, deployed |
| CRD/controller | CRD establishment and controller rollout checks passed |
| API/webhook admission | Zero-replica server-side dry run passed on both runs |
| Readiness scope | cpu_components_only; gpu_validation=skipped_debug |
| GPU/model/RDMA execution | Not performed |

Readiness generation matches the final platform descriptor. Both evidence timestamps fall within their corresponding successful deployment execution intervals. This Shell runtime did not export the optional deployment-ID variable, so the runner used its existing timestamp fallback for per-run folders. A regression test covers that case. Full local evidence is under `work/platform-debug/`; no tokens or PAR URLs are included in this report.

The pipeline had sufficient existing cluster authorization. The exported cluster-admin binding was not applied. The workstation's OBC proxy reached its local CONNECT endpoint, but TLS to the private API timed out; the bastion/API subnet lacks the corresponding private-API egress rule. A narrow rule was prepared for review but was not applied. It was not needed for the pipeline, whose runner uses the worker subnet inside the VCN. Existing network rules were left unchanged.

## Local verification and limits

Affected Terraform suites passed: ten infrastructure runs, nine publisher runs, nine discovery runs and one platform-module run. The actual configured debug ZIP passed five additional native tests, covering debug/normal planning, editable sizing and wrong-region rejection. Archive-resource verification also passed a separate saved-Plan/fresh-Apply worker check. Script/schema verification passed 38 checks with two optional local chart skips; the expanded bootstrap suite then passed all eleven cases, including timestamp fallback. The released LWS chart was fetched and installed live.

Normal GPU allocation, serving, CUDA/NCCL, RDMA transport, inference/benchmarking and model-only deployment/undeploy remain separate work. Before an RDMA allocation trial, the allocation module's separate Compute Cluster IAM policy also needs home-region provider routing. Platform names currently need to avoid collisions in tenancy-global bootstrap IAM names when adding other platform stacks. These follow-ups were not exercised by this CPU-only deployment.
