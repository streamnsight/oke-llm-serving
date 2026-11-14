<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Model discovery to OKE deployment

The workflow has three Terraform states: discovery, retained infrastructure/shared controllers, and a model-only deployment. The old combined deployment root has been removed.

1. Package/upload discovery, enter the model and workload assumptions, then Plan/Apply. Read the consolidated `discovery` output and choose any capacity-confirmed option's RMS URL. The optional HTML comparison link opens separately from RMS.
2. In the infrastructure stack, select an existing cluster in the chosen region. Review Plan before GPU allocation. Existing CPU pools host shared components. GPU pools/Compute Clusters remain retained and cannot be retired by a model change.
3. Run the required shared component pipelines. Monitoring defaults on; KEDA is opt-in; LWS follows topology. Reuse or configure compatible OKE-managed GPU/network support separately. A successful Terraform Apply is not runtime readiness.
4. Open infrastructure's `model_launch_url`. Its ZIP already contains the selected model/profile/recipe and the actual cluster/allocation/project/repository binding. Model Apply creates deploy, validate, benchmark and undeploy pipelines; it starts no inference.
5. Use `onboarding_arguments` with the platform's trusted onboarding pipeline. This grants exact model pipeline principals namespace-scoped permissions and bounded shared readiness reads. Model principals do not receive cluster administration or GPU infrastructure permissions.
6. Run model deploy. A checksum-verified local workload chart, with optional pinned router dependency, is published to OCIR and installed through a native Helm stage. Preflight checks ownership, the real allocation and selected prerequisites; final checks inspect the current release and serving endpoints.
7. Run validate or benchmark explicitly. Health/model identity checks support task-agnostic deployment; text probes and vLLM benchmark backends are explicit choices. Multimodal/audio models need appropriate test payloads/datasets. The CPU benchmark Job runs official `vllm bench serve`, records its native JSON and does not request a GPU.
8. Run guarded undeploy before destroying model pipeline metadata. It removes the owned release, drains its pods and preserves retained namespace/PVC/data and shared infrastructure. Trusted access revocation is separate and refuses active workloads.

There is no per-model project or evidence bucket. Scripts/specifications/values/reports use Generic Artifact Registry; charts use OCIR. Object Storage transports stack ZIPs and optional model weights. A pinned staged-weight manifest must still be materialized into a suitable local directory/PVC before serving; the CPU staging scratch volume is not a distributed model volume.

Prefix-aware routing is approximate cache locality, not a durable Responses conversation service. LMCache storage/connector requirements depend on the selected mode/image. See [component boundaries and missing adapters](model-layer-components.md), [model binding and commands](model-binding.md), [weight staging](model-storage.md) and [shared component ownership](infrastructure-bootstrap.md).

GPU inference, CUDA/NCCL/RDMA, actual cache hits, endpoint semantics and benchmark performance require hardware validation. Pipeline creation and successful rendering do not establish those properties.
