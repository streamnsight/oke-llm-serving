<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

# Model first deployment planning for OCI OKE

Proposal date November 11 2026

Current implementation update: the agreed first user-facing stack is now `terraform/stacks/discovery`, using native HTTP/OCI providers and HCL for model profiling and subscribed-region capacity. All Python/Bash model analyzers, external wrappers and precomputed-profile paths were removed. The second user-facing stack will allocate the selected region/OKE/shape/node quantity and create DevOps resources. Historical alternatives below describing interpreter-based discovery or a required bootstrap stack are superseded by this two-stack flow. See [current workflow](../docs/rms-discovery.md) and [implementation checklist](project-status.md).

## Purpose and product direction

Build a model-first advisor and reproducible deployment workflow for an existing regional OKE cluster. A user supplies a Hugging Face model and OCI context. The advisor inspects model artifacts, workload requirements, cluster compatibility, resource entitlements and reported capacity, then explains deployable configurations. The selected configuration becomes an immutable deployment specification consumed by Terraform and OCI DevOps.

The product must distinguish four questions: can the model fit, can the configuration meet the workload target, may this tenancy allocate the resources, and can OCI supply the capacity now? A successful quota check answers only the third question. A capacity report is an observation, not a reservation or a future launch guarantee.

This proposal authorizes no infrastructure deployment. The initial product concept and MVP scope should be approved before an implementation plan is finalized.

## Personas and user stories

| Persona | Need | User story |
|---|---|---|
| Model owner | Deploy without knowing GPU shapes | Given a model and usage goal, I can compare feasible configurations and understand why each fits or fails |
| Tenancy or platform administrator | Control placement, costs and shared cluster changes | I can constrain compartments, regions, shape families and installable components before approving deployment |
| Service operator | Maintain reliability despite scarce capacity | I can retain an allocated GPU floor, see readiness and capacity risks, and recover without blindly terminating working nodes |
| Infrastructure engineer | Reproduce and audit a deployment | I can recreate the selected configuration from pinned Terraform, model revisions and chart/image versions |

The full product can eventually include a browser wizard, multi-region cluster creation, performance profiling, reservations and capacity-acquisition workflows, shared service catalog, multiple runtimes, and stateful conversation services. The first pass should expose the same domain model through a CLI and structured reports so that a UI can be added without reimplementing discovery and planning.

## User workflow

1. Enter a Hugging Face model repository or URL. Resolve a revision and inspect metadata without downloading all weights.
2. Select an existing OKE cluster or supply tenancy, region and cluster identifiers. Discover accessible context rather than requiring knowledge of GPU shapes.
3. Choose an intended use: evaluation, interactive production, high-throughput generation or long-context service. Ask for context length and concurrency using plain descriptions, with editable assumptions.
4. Inspect current cluster capacity and available CPU headroom, candidate GPU shapes, entitlement headroom and reported host capacity.
5. Present configurations with total node/GPU counts, memory estimates, topology, deployment compatibility, allocation risk and estimated cost when a reliable price source exists.
6. Let the user select a configuration and review an explicit deployment specification and Terraform plan.
7. Recheck volatile capacity and permissions, then provision the selected resources. Keep acquired capacity while installing and validating the service.
8. Return the endpoint, API capabilities, actual deployed topology and benchmark/health evidence. Show how to scale workloads without releasing scarce machines.

The user should see meaningful states such as Fits with these assumptions, Needs lower concurrency, Limit increase required, Capacity reported unavailable, Capacity unknown, Reserved, Provisioning and Ready. A missing permission or unsupported capacity query must never be shown as zero capacity.

## Architecture options

| Option | Benefits | Costs and limits |
|---|---|---|
| Terraform-only discovery and deployment | One familiar tool and direct provider reuse | Awkward model analysis, dynamic region enumeration, interactive comparison, volatile capacity and estimates; mixes observation with resource ownership |
| Model-analysis tool plus native OCI Terraform | Structured discovery, testable model analysis, explainable comparisons, explicit reproducible deployment input | Two cooperating components with a versioned contract |
| Browser portal from the beginning | Most approachable interface and shared deployment catalog | Adds authentication, backend operations, persistent state and UI work before feasibility tooling is proven |

Current direction: Python for Hugging Face model analysis, native OCI Terraform data sources/resources for cloud discovery and infrastructure, and OCI DevOps coordinating Resource Manager and application deployment. RMS consumes precomputed model-profile JSON by default; it does not assume Python is installed. A portal can later present the same profiles and deployment specifications.

## Model inspection tool

Inputs: repository identifier, revision, optional access token reference and intended runtime. Outputs: a model profile with provenance and confidence for every inferred field.

Inspect config.json, tokenizer/chat-template metadata, model card, safetensors indexes/headers, file metadata, quantization metadata and adapter configuration. Select one coherent checkpoint variant; do not sum duplicate BF16, quantized and alternate-format files. Record missing information, gated access and unsupported/custom architectures explicitly. Metadata inspection must not execute remote repository code.

Extract architecture, dense versus MoE, total and active parameters where available, layers, attention/KV heads, head dimension, context constraints, vocabulary, tensor dtypes, quantization and multimodal components. For MoE, active parameters influence compute but total resident expert weights normally determine weight memory unless an explicitly supported offload strategy changes that assumption.

Weight file size, resident GPU weights and total runtime memory are separate estimates. Quantized formats can include scales and metadata, and an engine can transform or expand representations. Hybrid attention/state-space models, latent attention, sliding-window caches, multimodal encoders and speculative decoding need architecture-specific estimators or an explicit unsupported result.

Hugging Face Hub exposes model information and safetensors metadata inspection, including header/index parsing without requiring full weight downloads. [Hugging Face API reference](https://huggingface.co/docs/huggingface_hub/en/package_reference/hf_api).

## Memory and performance planner

There is no model-only answer to how much KV cache produces good performance. Required memory depends on context, simultaneous active sequences, prefix sharing, cache dtype, engine parallel layout and the latency/throughput objective.

For a conventional transformer, use an interpretable starting model:

```text
unsharded KV bytes ≈ 2 × layers × KV heads × head dimension
                      × live cached tokens × bytes per element

per-rank requirement = weight partition + KV partition/replication
                       + activation/workspace/communication allocations
                       + configured safety margin
```

Live cached tokens sum across active sequences. Account for maximum running requests, prompt/output lengths, prefix reuse assumptions and cache eviction. TP does not necessarily divide KV evenly, especially with few KV heads; model supported replication and divisibility constraints. PP partitions layer state but introduces stage and performance constraints.

Enumerate validated candidate layouts rather than every mathematically possible TP/PP/EP permutation. Reject layouts with incompatible attention head partitioning, runtime/model support, per-rank memory, node topology or OKE image support. Present at least a minimum-fit estimate and a production-headroom estimate. High availability requires complete independent replicas, not extra ranks inside one replica.

Performance status should progress from analytical estimate to recipe-based estimate to benchmark-validated configuration. Avoid publishing an unmeasured requests-per-second or latency promise. A later profiler should search compatible engine settings and record results for the exact model revision and hardware.

The analytical work is small relative to cloud deployment: bounded metadata reads plus candidate evaluation over shapes and validated layouts. Cache stable model/catalog data by revision; bound regional API concurrency and retries independently. No full checkpoint download is required merely to compare candidates.

## OCI discovery and hardware catalog

Discovery has separate passes:

- Identify subscribed regions and ADs; restrict deployable candidates to the selected cluster region in the first pass. Other regions can be shown as alternatives requiring another cluster.
- Inspect cluster type, Kubernetes version, network/API reachability, node pools, images, installed CRDs/controllers and resource requests/allocatable capacity.
- List compartment- and image-compatible shapes. Extract GPU count/description, CPU, host memory, local disks and RDMA ports/bandwidth.
- Query relevant limits, usage and resource availability in their documented scopes. Use shape quota names and maintained mappings rather than guessing limit-name strings.
- Preserve unsupported queries, denied access and partial region coverage as unknown states with reasons.

OCI shape metadata includes rdma_ports and rdma_bandwidth_in_gbps. memory_in_gbs is host memory, not per-GPU VRAM. A maintained catalog should supply per-GPU VRAM, intra-node NVLink/NVSwitch/XGMI topology, supported precisions, GPU count, fabric requirements and validated runtime/image combinations. Each catalog field needs a source, date and override history; unknown topology must not be inferred from a GPU marketing name.

After allocation, validate device inventory, topology and network operation using NVIDIA/AMD tooling and appropriate collective/transfer tests. Catalog support, configured fabric and working RDMA are three distinct states.

[Shape data source](https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/d/core_shapes.html), [limits availability and unsupported-query behavior](https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/d/limits_resource_availability.html), [compute shape specifications](https://docs.oracle.com/en-us/iaas/Content/Compute/References/computeshapes.htm).

## Capacity assessment and acquisition

CreateComputeCapacityReport reports host capacity for shape configurations within an AD, with optional fault-domain scope. Its response includes available_count and statuses AVAILABLE, OUT_OF_HOST_CAPACITY and HARDWARE_NOT_SUPPORTED. Preserve the raw observation, scope, timestamp and requested instance count. Count instances first, then multiply by GPUs per instance.

The query does not reserve hardware. Counts can change between discovery and apply, and aggregate host counts do not prove that a multi-node RDMA/compute-cluster placement can be satisfied. For unsupported shapes or missing fields, return unknown and identify the required allocation or service-team check. Do not interpret HARDWARE_NOT_SUPPORTED automatically as a tenancy-wide permanent absence of that GPU.

Capacity reservations are a separate acquisition mechanism. OKE supports reservations for managed nodes, but validate the exact shape, entitlement, AD/FD and placement combination before offering one. Creating a reservation may itself fail due to capacity and can incur charges. A successful report cannot substitute for a reservation or successful target allocation.

Do not use repeated launch-and-terminate probes by default. They incur real allocation/cost and can aggravate the delayed-reuse problem described by the user. When actual allocation is necessary, allocate the intended target pool and retain it for deployment. Failed application installation should preserve acquired capacity for diagnosis and retry unless a user-selected cleanup policy says otherwise.

The reported several-hour release delay is an operating constraint supplied by the user, not a documented universal OCI duration established by this research. The product should assume reacquisition is uncertain instead of predicting a fixed cooldown. Record observed allocation outcomes without claiming to predict when individual hosts return to inventory.

[Capacity-report Terraform resource](https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/r/core_compute_capacity_report.html), [capacity response fields](https://docs.oracle.com/en-us/iaas/tools/python/latest/api/core/models/oci.core.models.CapacityReportShapeAvailability.html), [OKE reservations](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengmakingcapacityreservations.htm).

## OKE placement and infrastructure

The existing cluster is regional. For the first pass, require GPU nodes in its region and compatible network placement. Treat another region as a separate cluster deployment, not another remote worker pool on this cluster.

Use managed GPU nodes for the initial supported configurations. For multi-node RDMA, OCI documents managed node pools in compute clusters on supported RDMA-capable bare-metal shapes. Adding such a pool to an existing cluster requires an enhanced cluster. The compute-cluster association must be chosen at pool creation and cannot be patched into an existing pool. Placement is constrained to that compute cluster's AD, and the documented procedure says not to specify fault domains.

Infrastructure modules should accept an existing cluster and networks, create dedicated GPU pools, optionally add CPU pools, configure placement and supported reservations/fabric resources, and provision storage and IAM references. Detect existing GPU drivers/device management before adding another controller; avoid conflicting GPU-operator installations.

CPU capacity should be evaluated from allocatable resources minus scheduled requests, system overhead and service requests. Router, metrics, controllers, model downloaders and optional API/history services need CPU/RAM and storage. Reuse sufficient existing CPU pools; create an extra pool only when required or explicitly requested.

[OKE compute-cluster integration](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengusingcomputeclusters.htm), [node-pool Terraform resource](https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/r/containerengine_node_pool.html), [specialized hardware management](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengmanagingspecializedhardwaredevices.htm).

## Serving and scaling policy

Keep a small, validated recipe catalog: model architecture and engine version, supported shape/topology, required controllers, chart version, container digests, memory assumptions and health checks. Recipes are technical adapters; users choose an outcome rather than naming CRDs.

The first deployment adapter can use production-stack with vLLM because its source has already been investigated. Its Deployment, Ray and P/D scaling paths are not interchangeable. Supporting one adapter initially does not imply selecting it as the only long-term platform. Later adapters can target LWS/DS with llm-d, Dynamo or SGLang.

Separate model replica scaling from GPU machine release. Proposed default for scarce production capacity: retain the selected GPU node floor, scale workloads within that allocation, and require an explicit policy change before lowering the floor. CPU pools can have independent autoscaling. Capacity-aware scale-up can recheck reports, but a favorable report should not trigger speculative GPU termination.

If Cluster Autoscaler owns node-pool size, Terraform must use a deliberate lifecycle/ownership contract so subsequent applies do not reset it. Similarly, one supported controller should own model replica counts. Use bounded retry and terminal error states for allocation failures; never silently switch model precision, region or shape after approval.

Responses plus durable conversation history remains a separate service option. production-stack forwarding and LMCache alone do not supply that contract. The first infrastructure MVP can explicitly expose stateless inference; if conversation IDs are required for its acceptance, add a shared stateful API service and database as a defined work package rather than implying it is included.

## Versioned tool contracts

Proposed tools, callable from CLI now and a UI or agent later:

| Tool | Output |
|---|---|
| inspect_model | ModelProfile with source revision, artifact selection and estimation confidence |
| inspect_cluster | ClusterProfile with compatibility, installed components and allocatable/requested resources |
| discover_accelerators | GPUInventory with subscribed-region coverage, shapes, entitlements and existing allocations |
| assess_capacity | CapacityAssessment scoped by shape/AD/FD with status and observation time |
| propose_deployments | Feasible and rejected candidates, memory arithmetic, topology and reasons |
| materialize_deployment | Selected DeploymentSpec and Terraform variable artifacts |
| validate_deployment | Runtime device checks, endpoint checks and benchmark evidence |

Cache profiles independently. A deployment specification pins model SHA, artifact digest where available, runtime/chart/image versions, region, cluster, shape, node counts, placement, parallelism, replica counts and memory configuration. Capacity observations are attached evidence with expiration, not timeless configuration values. Tokens and keys are references to secrets, not plaintext in reports or generated tfvars.

## Terraform and delivery workflow

Terraform should own durable OCI infrastructure and the bootstrap/pipeline configuration. Keep discovery, ranking and benchmarking in tools rather than embedding them as shell provisioners in a large apply.

Suggested delivery stages:

1. Run discovery and model analysis; produce candidate report.
2. Select an explicit DeploymentSpec and commit/version the configuration.
3. Validate Terraform, chart schemas, recipe compatibility and permissions.
4. Produce an infrastructure plan and cost/capacity summary.
5. Recheck volatile capacity immediately before allocation and apply through Resource Manager.
6. Wait for nodes and validate GPUs/fabric.
7. Install shared components through a separately owned foundation stage; install model-specific charts afterward.
8. Perform endpoint, recovery and performance checks; publish results and endpoint details.

Use separate states/stages for shared cluster foundation and model deployments. A user deleting one model must not remove another team's gateway or monitoring. Multiple model deployments must reuse cluster-scoped controllers rather than race to install competing CRDs.

OCI Resource Manager provides Terraform execution, stored state and locking; DevOps supplies orchestration, artifacts and shell/Helm stages. A DevOps shell stage can invoke Resource Manager with resource-principal authentication. Private OKE endpoints require runner/private-endpoint reachability and DNS/NSG configuration. Bootstrap the initial DevOps/Resource Manager resources once, then use them for repeat deployments; avoid a pipeline that depends on itself existing before its first apply.

Kubernetes/Helm resource ownership can be either Terraform Helm-provider states or DevOps Helm stages, but not both for the same release. Proposed preference is Terraform for infrastructure and DevOps for staged Helm delivery, with Terraform provisioning the pipeline definitions as code. This achieves reproducibility without making a single Terraform transaction responsible for every model startup.

[DevOps with Resource Manager](https://docs.oracle.com/en/learn/rm-ocidevops/), [shell stages](https://docs.oracle.com/en-us/iaas/Content/devops/using/shell_stage.htm), [private access](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/private-endpoints.htm), [Terraform deployment-stage resource](https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/r/devops_deploy_stage.html).

## Proposed MVP and subsequent scope

### Initial MVP

- Existing same-region OKE cluster; discovery inspects whether basic/enhanced type meets the chosen recipe.
- Model-analysis CLI and native Terraform discovery outputs; no portal required.
- Hugging Face safetensors metadata, dense and explicitly recognized MoE architectures; uncertainty reported honestly.
- NVIDIA shapes with a small curated topology catalog, live OCI shape/limit/capacity queries and partial-permission handling.
- Comparison of single-GPU, single-node multi-GPU and supported multi-node layouts; unsupported configurations rejected with explanations.
- First deployment recipe for single-node vLLM/production-stack, using one or more complete replicas. Multi-node deployment follows after fabric validation; discovery/schema design supports it from the start.
- Dedicated GPU pool, optional extra CPU pool, storage, metrics and fixed minimum GPU capacity.
- Resource Manager and DevOps delivery definitions, with pinned inputs and deployment validation.

### Later increments

Validated RDMA compute-cluster multi-node deployment; LWS/DS or alternative serving adapters; P/D serving; performance calibration; supported capacity reservations and acquisition workflows; durable conversation API; additional vendors; multi-region cluster creation; web wizard and shared deployment catalog.

The main MVP scope decision is whether multi-node deployment and durable Conversations must ship in the first release. Including either expands validation substantially; both should have explicit acceptance criteria rather than being incidental extras.

## Phased execution plan

### Phase 0 Approve the product contract

- [ ] Confirm full workflow, supported model families and MVP boundaries.
- [ ] Choose the first deployment recipe and fixed-capacity policy.
- [ ] Decide whether initial acceptance requires multi-node serving and durable conversation IDs.
- [ ] Select a test tenancy/compartment and existing OKE cluster when implementation begins.

### Phase 1 Implement discovery and estimation

- [x] Define versioned model profiles, evidence and confidence states.
- [x] Implement Hugging Face metadata inspection and initial conventional-attention estimators, with unsupported results for other architectures.
- [x] Implement Native OCI Terraform region/shape/limit/capacity discovery with live DEFAULT-profile validation.
- [ ] Implement OKE cluster and existing-allocation discovery.
- [ ] Seed the sourced hardware catalog.
- [ ] Verify gated models, duplicate formats, MoE sizing, unsupported limits, permission failures and partial results.

### Phase 2 Implement candidate planning

- [ ] Enumerate compatible shape/node/parallel layouts with bounded search.
- [ ] Explain memory requirements, entitlement constraints and capacity status independently.
- [ ] Generate selected DeploymentSpec and Terraform inputs.
- [ ] Verify arithmetic, per-rank constraints, shape granularity and deterministic reproduction.

### Phase 3 Implement infrastructure and delivery

- [ ] Build existing-cluster, GPU-pool, optional CPU-pool and storage/IAM modules.
- [ ] Add Resource Manager/DevOps bootstrap and staged execution.
- [ ] Install the selected model recipe and required shared components with explicit ownership.
- [ ] Verify private-network access, node readiness, GPU inventory and inference endpoint.

### Phase 4 Validate production behavior

- [ ] Benchmark representative context/concurrency profiles and compare estimated memory to actual allocation.
- [ ] Test capacity failure, interrupted apply, application failure after GPU allocation and retry without node replacement.
- [ ] Test model rollouts and fixed GPU floor under workload scale-down.
- [ ] Confirm repeat apply is stable and model teardown preserves shared cluster resources.

### Phase 5 Extend topologies and user experience

- [ ] Add validated multi-node fabric recipes and collective tests.
- [ ] Add conversation state and additional serving adapters as approved.
- [ ] Add the web workflow over the existing tools.

Success for the first implementation is a user choosing a model without knowing GPU shapes, receiving an explainable feasible configuration with honest capacity evidence, and deploying a reproducible tested endpoint into the existing cluster without accidental release of scarce GPU capacity.

## Refined RDMA modules and staged user workflow

### Managed RDMA pools

Current OKE documentation explicitly supports managed node pools on RDMA-capable bare-metal shapes through a Compute Cluster. The sequence is to create the empty Compute Cluster, wait until ACTIVE, and create a managed node pool referencing it. OKE launches nodes into the group; the group itself does not allocate GPU hosts or reserve capacity. An enhanced OKE cluster, compatible shape/image, same-AD placement and required IAM are prerequisites. Do not specify fault domains for this compute-cluster pool. The association is immutable after pool creation.

The node pool remains scalable. OKE documents Cluster Autoscaler for managed pools, including GPU requests, and documents scaling as a retained operation for compute-cluster pools. These facts support the architecture, but end-to-end behavior for the selected OKE/autoscaler/shape version still needs validation. No autoscaler can guarantee fresh host capacity or sufficient capacity for a distributed gang. The initial product will retain fixed GPU allocation and scale inference workloads within it.

This path differs from older self-managed-node deployments using Cluster Networks and instance pools. A deployment adapter must not mix those ownership models.

[Managed compute-cluster pools](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengusingcomputeclusters.htm), [Compute Cluster Terraform resource](https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/r/core_compute_cluster.html), [OKE Cluster Autoscaler](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengusingclusterautoscaler.htm).

### Proposed module boundaries

| Module | Inputs | Outputs and ownership |
|---|---|---|
| model_profile | HF repository/revision, context, concurrency, dtype and runtime | Resolved model profile, memory assumptions, compatible architecture facts; no allocated hardware |
| accelerator_inventory | Tenancy/compartment, selected region, cluster and catalog version | Shapes, limits, usage, quota observations, existing GPU capacity and compatibility |
| capacity_assessment | Candidate shapes, ADs and shape configs | Timestamped capacity reports and explicit unknown/unsupported outcomes |
| deployment_planner | Model profile, inventory, capacity evidence and user constraints | Candidate layouts plus rejection reasons; no resource mutation |
| gpu_allocation | Selected immutable deployment specification | Optional Compute Cluster plus GPU managed node pool, optional CPU pool, storage/IAM references |
| delivery_pipeline | Allocated resource IDs and pinned deployment artifacts | DevOps deployment environments, artifacts, stages and configuration |

Modules are reusable code units, not necessarily separate Resource Manager stacks. OCI inventory uses native data sources and capacity assessment uses a native report resource. Model analysis uses native HTTP data sources and Terraform expressions. No OCI SDK, interpreter or external script is required.

The model_profile module accepts a public model URL and serving assumptions directly. It reads Hub-published safetensors counts and SHA-pinned config JSON, with declared metadata provenance. Independent tensor-header inspection, gated/private access and alternate checkpoint selection are outside the initial implementation. RMS does not require a precomputed profile.

The capacity API's Terraform implementation is a resource, oci_core_compute_capacity_report, rather than a data source. It creates a report, not instances. A module can expose its results but needs an explicit freshness strategy; re-reading an old report is not a fresh host-capacity test. Change observation_id to deliberately create a fresh native report for the discovery run and again before allocation. The provider documentation requires the report compartment to be the tenancy root. Limits and target-compartment quota observations have different scopes and must remain separate.

[Terraform external protocol](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external), [capacity report lifecycle](https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/r/core_compute_capacity_report.html).

### RDMA selection and fallback

Offer rdma_policy with required, preferred and disabled settings. During candidate planning, preferred can consider a compatible regular managed node pool when RDMA is unavailable. The alternative must still fit memory and an acceptable performance envelope. A single-node model may not need inter-node RDMA. A multi-node configuration dependent on high-speed collectives cannot be declared equivalent after merely removing the fabric.

Freeze the actual network mode in the selected specification. An allocation failure must not silently trigger deployment of a different topology inside the same Terraform apply. Replan and present the alternative, preserving already acquired hosts where practical. Capacity exhaustion, missing permissions, unsupported shapes and cluster-type incompatibility require different outcomes.

### Resource Manager stack structure

Proposed ownership uses three logical stacks:

1. Bootstrap, once per platform environment. Creates the artifact location, discovery/coordination DevOps resources, Resource Manager stack definitions and narrow IAM. It solves the initial pipeline-existence problem. It does not own model GPU nodes.
2. Discovery, reusable per deployment request or isolated investigation. Runs model and OCI assessment, publishing model-profile.json, inventory.json, capacity-assessment.json and candidates.json. If Terraform owns only data sources, an apply can publish job outputs/state without allocating GPUs. If the report resource is used, that apply also creates the report. An external DevOps discovery stage can replace this stack without changing the contract.
3. Allocation, one per deployment or explicitly shared capacity unit. Takes only an approved deployment specification; creates the selected node pool/fabric and optional CPU/storage capacity plus model delivery pipeline definitions. It does not rerank shapes during ordinary drift reconciliation.

The optional shared cluster foundation is an ownership boundary managed by platform DevOps stages or its own stack if Terraform owns those resources. It is not recreated per model. Individual model releases are deployed by DevOps, so they need not each become another Resource Manager stack.

Multiple stacks are a design choice for state and ownership, not a requirement imposed by each sequential step. Within allocation, Terraform can create Compute Cluster then node pool then DevOps resources using ordinary dependencies. Separate jobs are required where human configuration selection or runtime validation intervenes.

Resource Manager does not automatically chain arbitrary stack outputs into downstream variables. The coordinator reads completed job outputs or versioned artifacts, validates their schema and passes explicit inputs to the next stack. Prefer exported artifacts over broad access to another stack's entire state. Resource Manager provides a job-output API for completed apply jobs.

[Resource Manager outputs](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/list-job-outputs.htm), [publishing Terraform data across configurations](https://developer.hashicorp.com/terraform/language/state/remote-state-data).

### User workflow and reproducibility

Expose one request with three actions: Assess, Select configuration and Deploy. Terraform stages remain an implementation detail. The first UI can be a CLI with a readable report; Resource Manager's variable form is useful for fixed inputs but is not a complete live recommendation wizard.

Assess writes a timestamped discovery-run artifact. Select produces deployment-spec.json with model SHA, estimator/catalog versions, selected shape/node counts, topology, engine settings, retained GPU floor and expected cost assumptions. Deploy plans the allocation stack, rechecks capacity without changing the approved selection, allocates nodes and triggers DevOps installation/validation. Approval of a pipeline stage alone must not be mistaken for selecting arbitrary model/shape parameters; the selected artifact must already exist.

Use content hashes or immutable version identifiers for cross-stage artifacts. Repeated discovery must not rewrite the specification of an already deployed model. If the same request is retried after partial failure, the coordinator should resume against its existing allocation stack and acquired nodes. Shared-component installation must be serialized or otherwise coordinated across concurrent model requests.

The HF model-profile tool, opt-in local wrapper, runtime-free profile input, native OCI inventory and capacity modules are implemented and locally validated. Next work is the hardware topology/VRAM catalog, OKE inspection and candidate planning before infrastructure allocation.
