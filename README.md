<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# OCI OKE LLM serving

A model-first workflow for an existing OKE cluster: discover the model and available GPU choices, provision retained GPU infrastructure/shared controllers, then manage model releases independently. Model deployment must never resize or destroy the GPU allocation.

## Start with discovery

```sh
make package
```

Upload `work/packages/oke-llm-discovery.zip` to OCI Resource Manager, using the ZIP root as its working directory. Enter a public Hugging Face model URL/ID, context length and concurrent sequences per replica. Empty region/shape filters scan READY subscribed regions and visible GPU shapes. Discovery allocates no GPUs.

The only RMS output is **Open discovery report**, a link to a self-contained HTML page in the private discovery bucket:

- Model identity/revision, type, layers/attention dimensions, parameter/dtype counts, checkpoint formats and weight size.
- Memory requirements for the entered context/concurrency: resident weights, KV cache, runtime allowance, margin and estimation limits.
- Every eligible region/AD/shape option, with observed host/GPU capacity, entitlement, requested hosts, GPUs per replica, allocated/unused GPUs and complete replicas that fit the allocation.
- Collapsed options with planned/upstream recipe commands, image/configuration provenance, required components and separate infrastructure/model PAR and regional RMS URLs.
- Useful exclusions when no option is available; detailed diagnostics are opt-in.

Capacity is an observation, not a reservation. Counts for alternative shapes and repeated quota ceilings must not be added together. Unsupported memory remains unknown. GB and GiB are labeled distinctly.

The page uses the supplied Redwood styling and embeds its JSON, styles and scripts. RMS opens it separately through an expiring read PAR; there are no additional JSON outputs. It is published even with zero viable options, showing regional capacity, entitlement and potential limit-increase reviews.

For local Terraform use:

```sh
terraform init
terraform plan -var-file=/path/to/request.tfvars.json -out=work/discovery.tfplan
terraform apply work/discovery.tfplan
terraform output -raw comparison_report_url
```

Recipe metadata is shared across profiling, serving resolution and planning. Hardware render requests are deduplicated; unselected nightly/cache alternatives do not run during ordinary discovery. HF/recipe lookup uses Terraform HTTP/HCL. Regional OCI lookup uses one module-owned OCI CLI/Bash/jq scanner, with no nested Terraform, custom Python or Go program.

## Infrastructure, then model deployment

1. Choose any infrastructure RMS link in discovery. Its ZIP contains editable recommendations; select an existing OKE cluster in that region. Existing CPU pools host controllers. The infrastructure owner manages GPU pools/Compute Cluster placement, shared controllers, one DevOps project, its OKE environment and artifact repositories.
2. Run shared component pipelines as required. Prometheus defaults on; KEDA is opt-in; LWS follows topology. Reuse OKE GPU/network add-ons. Known missing native prerequisites block enhanced-cluster GPU allocation; automatic add-on configuration and GPU exporter scraping remain unfinished.
3. Open the **model stack link already present in discovery**. Select the cluster; matching managed pool, networking and shared capabilities are inferred. Each model gets an independent DevOps project, OKE environment, artifact repositories and pipelines. Metadata creation can precede GPU/controller deployment; it does not start inference.
4. Grant the model principals namespace-scoped access through the trusted platform onboarding pipeline. Then run model deploy, validate, benchmark or undeploy independently. GPU execution remains a separate hardware-validation step.

The model release uses a repository-owned workload chart for Deployment or LWS instances and an optional pinned upstream Production Stack router dependency. Shared operators/CRDs are not installed by the model release. Multiple packed replicas default to prefix-aware routing; this is distinct from event-driven KV routing and durable conversation history.

Scripts, specifications, values and execution reports use Generic Artifact Registry. Helm charts use OCIR. Object Storage holds discovery/model stack bundles and optional retained model data. No software-artifact evidence bucket is created by the model stack.

Undeploy removes only the owned model release and its model-specific resources. It preserves namespaces, retained data, shared controllers and GPU hosts. Revoke access before destroying the model's metadata/project. Terraform destruction of pipeline definitions alone does not uninstall an imperative Helm release; use the explicit guarded undeploy flow first.

## Current validation limits

The shared CPU component flow was validated live: LWS reuse, parallel Prometheus/KEDA installation, fresh readiness, and KEDA uninstall/reinstall retaining its six CRDs. The model-only workflow is being validated for Terraform, chart/script behavior, packaging and RMS pipeline creation with GPU allocation disabled. Actual GPU placement, CUDA/NCCL/RDMA, inference, cache hits and performance require later GPU testing.

A vLLM operator is optional. LMCache does not universally need a database: local RAM/disk, remote stores and multiprocess/P-D transfer have different requirements. Recipe connector flags do not provision those services. Native Responses forwarding or `previous_response_id` support does not establish durable, shared conversation state. See [component ownership and missing capabilities](docs/model-layer-components.md).

## Layout and development

Discovery is the repository root. Modules are grouped under `modules/discovery`, `modules/infrastructure`, `modules/cluster-add-ons`, `modules/llm-deployment` and `modules/shared`. Downstream roots are `templates/infrastructure` and `templates/llm-deployment`. Runtime assets stay inside their owning modules. See [module ownership](docs/repository-layout.md).

CI publishes only the discovery entry ZIP, containing both downstream templates. `make package-infrastructure` and `make package-model` are developer builds; discovery generates both configured child ZIPs. Existing published objects/PARs do not change when a local ZIP is rebuilt; rerun discovery with the new source to generate updated launch links.

Useful documentation:

- [Project status](outputs/project-status.md) and [active implementation plan](outputs/discovery-html-report-plan.md)
- [RMS discovery inputs](docs/rms-discovery.md) and [model profile arithmetic](docs/model-profile.md)
- [Shared infrastructure/component lifecycle](docs/infrastructure-bootstrap.md)
- [Optional weight staging and its validation limits](docs/model-storage.md)
- [Serving ecosystem research](outputs/kubernetes-llm-serving-report.md)

Local state, request files, execution evidence and ZIPs stay in ignored `work/` or local state files. Node/YAML is a development-test dependency and is not shipped to RMS.
