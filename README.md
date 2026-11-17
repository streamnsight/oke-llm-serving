<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# OCI OKE LLM serving

A model-first workflow for an existing OKE cluster: discover the model and available GPU choices, provision retained GPU infrastructure/shared controllers, then manage model releases independently. Model deployment must never resize or destroy the GPU allocation.

## Start with discovery

[![Deploy to Oracle Cloud][magic_button]][magic_oke_llm_serving_stack]


Enter a public Hugging Face model URL/ID, context length and concurrent sequences per replica. Empty region/shape filters scan READY subscribed regions and visible GPU shapes. Discovery allocates no GPUs. Optional monitoring, autoscaling and model distribution are deployment-stage choices: shared components in infrastructure, model monitoring/scaling and weight delivery in the model stack.

The only RMS output is **Open discovery report**, a link to a self-contained HTML page in the private discovery bucket:

- Model identity/revision, type, layers/attention dimensions, parameter/dtype counts, checkpoint formats and weight size.
- Memory requirements for the entered context/concurrency: resident weights, KV cache, runtime allowance, margin and estimation limits.
- Every eligible region/AD/shape option, with observed host/GPU capacity, entitlement, requested hosts, GPUs per replica, allocated/unused GPUs and complete replicas that fit the allocation.
- Collapsed options with planned/upstream recipe commands, image/configuration provenance, required components and separate infrastructure/model PAR and regional RMS URLs.
- Capacity and effective limit headroom are always checked, including zero-limit shapes. Positive capacity needing higher limits is shown as an alternative; exclusions and memory assumptions are included automatically.

Recommendations prioritize hardware fit (VRAM and sharding), RDMA capability and quantity-confirmed growth headroom. GPU count is a later tie-breaker, with no throughput/cost prediction. Technical serving details appear below deployment actions; the capacity table shows only positive supply, including regions needing limit increases.

Capacity is an observation, not a reservation. Counts for alternative shapes and repeated quota ceilings must not be added together. Model sizing remains available independently of engine and hardware compatibility. Native checkpoint bytes provide a weight baseline; unfamiliar architectures receive an explicitly heuristic cache/workspace planning scenario. Missing metadata requires checkpoint selection or an explicit budget. Deployment options exclude incompatible or unverified dtype/kernel combinations; regional capacity can retain these GPUs with compatibility labels. GB and GiB are labeled distinctly.

Multi-host discovery uses intra-host tensor parallelism and cross-host pipeline parallelism when the pinned upstream supported-model table declares PP support. It considers up to `max_hosts_per_replica` (default 8), checks stage imbalance, KV-head replication, embedding overhead and per-GPU runtime, and requires capacity plus entitlement for every host in one AD. A fitting single-host configuration remains preferred. Multi-host estimates use the existing LeaderWorkerSet/mp adapter over Ethernet (`NCCL_IB_DISABLE=1`); the selected image, workload and network performance still require runtime validation. Coupled speculative/disaggregated modes need separate support and are not enabled by this adaptation.

Memory assumptions are editable in the discovery schema: `checkpoint_file` selects an ambiguous single-file variant, `weight_budget_gb` overrides the weight baseline, and `planning_budget_gb` supplies a complete payload budget when metadata is insufficient (decimal GB; zero selects automatic estimation). `unknown_cache_fraction` defaults to 0.25 of weights when attention dimensions are absent; `workspace_fraction` defaults to 0.10 for heuristic sizing. These allowances are uncalibrated scenarios, not guaranteed upper bounds. Workspace and proportional safety margin overlap: the payload adds the larger allowance rather than stacking both. GPU screening separately reserves runtime overhead per device and 10% device headroom. All MoE experts remain resident under the default no-offload assumption.


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
3. After retained infrastructure and shared components are ready, open the **model stack link already present in discovery**. Select the cluster; the managed pool, networking and trusted onboarding pipeline are inferred. Each model gets an independent DevOps project, OKE environment, artifact repositories and pipelines.
4. Model Apply automatically runs trusted namespace onboarding, workload deployment and independent validation, waiting for success. Benchmarking remains manual. Deploy, validate and guarded undeploy also remain independently rerunnable; the model stack never allocates or changes GPU hosts.

The model release uses a repository-owned workload chart for Deployment or LWS instances and an optional pinned upstream Production Stack router dependency. Shared operators/CRDs are not installed by the model release. Multiple packed replicas default to prefix-aware routing; this is distinct from event-driven KV routing and durable conversation history.

Small scripts, specifications and values use readable inline DevOps artifacts. Required file inputs and downloadable benchmark results use Generic Artifact Registry; routine deployment, readiness and failure reports go to DevOps logs. Helm charts use OCIR. Object Storage holds discovery/model stack bundles and optional retained model data.

New model stacks use a state-persisted instance suffix for their notification topic, project, log group and artifact repositories, and a separate default namespace. Two stacks for the same model can coexist without sharing ownership. Existing stacks retain their legacy names on source upgrades; explicit namespace overrides remain unchanged.

Undeploy removes only the owned model release and its model-specific resources. It preserves namespaces, retained data, shared controllers and GPU hosts. Revoke access before destroying the model's metadata/project. Terraform destruction of pipeline definitions alone does not uninstall an imperative Helm release; use the explicit guarded undeploy flow first.

## Current validation limits

The shared CPU component flow was validated live: LWS reuse, parallel Prometheus/KEDA installation, readiness, and KEDA uninstall/reinstall retaining its six CRDs. Model Apply now also passed live in Montreal: trusted onboarding, workload deployment and independent validation succeeded on the retained four-A10 worker. The unchanged recipe image runs with the Python frontend and an explicit direct-HF `main` override; the Pod is Ready with zero restarts and a bounded chat test returned `OK`. No GPU allocation or recycling was performed. Benchmarking, multi-node/RDMA operation, other inference modalities and cache/conversation persistence still require their own validation. See [the startup validation record](outputs/vllm-frontend-startup-plan.md).

A vLLM operator is optional. LMCache does not universally need a database: local RAM/disk, remote stores and multiprocess/P-D transfer have different requirements. Recipe connector flags do not provision those services. Native Responses forwarding or `previous_response_id` support does not establish durable, shared conversation state. See [component ownership and missing capabilities](docs/model-layer-components.md).

## Layout and development

Discovery is the repository root. Modules are grouped under `modules/discovery`, `modules/infrastructure`, `modules/cluster-add-ons`, `modules/llm-deployment` and `modules/shared`. Downstream roots are `templates/infrastructure` and `templates/llm-deployment`. Runtime assets stay inside their owning modules. See [module ownership](docs/repository-layout.md).

CI publishes only the discovery entry ZIP, containing both downstream templates. `make package-infrastructure` and `make package-model` are developer builds; discovery generates both configured child ZIPs. Existing published objects/PARs do not change when a local ZIP is rebuilt; rerun discovery with the new source to generate updated launch links.

Useful documentation:

- [Project status](outputs/project-status.md) and [active implementation plan](outputs/discovery-recommendations-plan.md)
- [RMS discovery inputs](docs/rms-discovery.md) and [model profile arithmetic](docs/model-profile.md)
- [Shared infrastructure/component lifecycle](docs/infrastructure-bootstrap.md)
- [Optional weight staging and its validation limits](docs/model-storage.md)
- [Serving ecosystem research](outputs/kubernetes-llm-serving-report.md)

Local state, request files, execution evidence and ZIPs stay in ignored `work/` or local state files. Node/YAML is a development-test dependency and is not shipped to RMS.

## References

[magic_button]: https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg
[magic_oke_model_serving_stack]: https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/streamnsight/oke-llm-serving/releases/latest/download/oke-llm-serving.zip