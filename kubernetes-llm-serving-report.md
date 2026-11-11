<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

# Kubernetes LLM serving from GPU resources to conversation APIs

Research date: November 10, 2026

Supporting single-GPU, multiple-GPU and multiple-node LLM serving requires several cooperating layers. Kubernetes allocates devices and places pods; workload controllers manage distributed replicas; serving engines partition weights and execute inference; inference routers select workers; cache systems reuse tensors; and an API service retains conversation history. A platform can package several of these responsibilities, but they remain distinct operational concerns.

This report maps those layers and the major open-source options, explains where they excel, and provides deployment patterns by use case. The scope is the Kubernetes inference ecosystem and important adjacent systems, rather than every experimental operator or managed cloud product. Comparisons describe architectural fit, not a universal performance ranking. Documentation marked `latest`, `dev` or `main` can include capabilities beyond a particular released image; pin and verify the complete deployment combination.

## 1 The stack and its responsibilities

The following is the order in which to understand and assemble the infrastructure. Request traffic travels in the opposite direction through the serving layers.

| Layer | Question it answers | Kubernetes resources or components |
|---|---|---|
| Physical capacity | Which machines and interconnects exist? | GPU nodes, NVLink/NVSwitch, PCIe, InfiniBand/RoCE/EFA, local NVMe |
| Device enablement | How does a container obtain a GPU or NIC? | GPU Operator, device plugins, DRA drivers, device claims |
| Node provisioning | Where does additional machine capacity come from? | Cluster Autoscaler, Karpenter, cloud or bare-metal provisioner |
| Quota and admission | Which team or service may consume capacity now? | Kueue queues, flavors and Workloads; admission policies |
| Pod placement | Can all required pods fit with suitable topology? | kube-scheduler, native Workload/PodGroup, Volcano, scheduler plugins |
| Workload lifecycle | Which pods together constitute a serving replica? | Deployment, StatefulSet, LeaderWorkerSet, DisaggregatedSet, Grove, RayCluster |
| Model lifecycle | Which model, runtime and service should run? | KServe, Dynamo, AIBrix, KAITO, RayService and other serving control planes |
| Inference execution | How are weights, layers and requests distributed? | vLLM, SGLang, TensorRT-LLM and other engines |
| KV management | Where are computed attention tensors kept and reused? | Engine cache, LMCache, HiCache, Mooncake, Dynamo cache components, NIXL transfer |
| Inference routing | Which model replica or prefill/decode pair should handle a request? | InferencePool, endpoint picker, llm-d router, Dynamo router, SGLang Model Gateway |
| API governance | Who can call which model and under what quota? | LiteLLM, Kong, Agent Router, agentgateway, Portkey, Bifrost, Higress |
| Conversation state | How does an ID recover previous messages and tool results? | Stateful Responses/Conversations service and a shared database |

**Three different scheduling problems occur here:** scheduling pods onto nodes, routing HTTP requests to serving replicas, and scheduling token batches inside the inference engine. Kueue and Kubernetes scheduling do not replace the latter two.

## 2 Native Kubernetes building blocks

### 2.1 Pods and ordinary workload controllers

A single pod can request multiple GPUs from one Kubernetes node. A request for eight GPUs is not automatically spread across eight nodes. All containers in a pod run on the same node; using several nodes requires several pods and an engine capable of distributed execution.

For a one-GPU replica, a Deployment usually suffices. It can also run a replica that uses two, four or eight GPUs on one node. A StatefulSet adds stable identities and storage associations, but does not itself create a distributed model or enforce collective startup. Jobs and Indexed Jobs describe finite work, such as checkpoint preparation and batch inference. DaemonSets are appropriate for per-node device drivers and telemetry agents.

Core supporting resources include Services and EndpointSlices for discovery, headless Services for worker identity, PVCs and StorageClasses for artifacts, Secrets for model access, PriorityClasses for scheduler priority, and PodDisruptionBudgets for voluntary disruption. Readiness must mean that model weights are loaded and the distributed ranks can serve, not merely that a process is alive. A disruption budget is not a guarantee against machine failure or every controller-driven rollout.

[Kubernetes GPU scheduling](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/), [workload controllers](https://kubernetes.io/docs/concepts/workloads/controllers/), [disruption budgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/).

### 2.2 Native Workload and PodGroup in Kubernetes 1.37

Your observation is correct: the native `Workload` and `PodGroup` APIs are beta in Kubernetes 1.37, in `scheduling.k8s.io/v1beta1`. The current concept pages say that `GenericWorkload` is disabled by default and must be enabled on the relevant components. An available beta API therefore does not mean that every managed Kubernetes offering enables it.

`Workload` defines scheduling policy templates. `PodGroup` is a runtime instance of cooperating pods and carries scheduling policy and status. A gang policy with a minimum count tells the scheduler that the group needs sufficient members to be schedulable together. This helps avoid leaving half of a distributed model holding GPUs while the other half cannot start.

These APIs do not load model shards, implement distributed collectives, retain KV tensors, or replace the workload controller. Also, `PodGroupInitiallyScheduled` records the initial scheduling outcome; it does not remain a live health signal after later pod failures. Newer hierarchical/composite scheduling features have their own gates and maturity, which must be checked separately.

[Workload API](https://kubernetes.io/docs/concepts/workloads/workload-api/), [PodGroup API](https://kubernetes.io/docs/concepts/workloads/podgroup-api/), [1.37 scheduling changes](https://kubernetes.io/blog/2026/09/08/kubernetes-v1-37-advancing-workload-aware-scheduling/).

### 2.3 Identical kind names do not mean identical APIs

| Resource | API family | Meaning |
|---|---|---|
| Native Workload | `scheduling.k8s.io` | Workload scheduling policy templates |
| Native PodGroup | `scheduling.k8s.io` | Runtime scheduling group |
| Kueue Workload | `kueue.x-k8s.io` | Quota and admission representation of managed work |
| Volcano PodGroup | `scheduling.volcano.sh` | Group used by Volcano scheduling |
| Scheduler plugins PodGroup | `scheduling.x-k8s.io` | Group used by the scheduler-plugins coscheduling implementation |

Always identify a resource by API group, version and kind. Installing one PodGroup CRD does not satisfy a controller expecting another. Native scheduling resources are built-in APIs, not CRDs. HPA is also built in; VPA, KEDA and LWS use installed custom resources.

[Native PodGroup reference](https://kubernetes.io/docs/reference/kubernetes-api/scheduling/pod-group-v1beta1/), [Kueue concepts](https://kueue.sigs.k8s.io/v0.20/docs/concepts/), [Volcano](https://github.com/volcano-sh/volcano), [scheduler plugins coscheduling](https://github.com/kubernetes-sigs/scheduler-plugins/tree/master/pkg/coscheduling).

## 3 GPU enablement and topology

### 3.1 Device plugins and GPU operators

The established device-plugin path advertises extended resources such as `nvidia.com/gpu`. The pod requests an integer count; the scheduler places it on a node with that advertised capacity, and the device integration makes allocated devices accessible inside the container. NVIDIA GPU Operator packages driver, container runtime integration, device plugin and telemetry management. Equivalent vendor stacks exist for AMD and other accelerators.

Whole-device allocation is straightforward but can waste capacity for small models. MIG partitions supported GPUs into hardware instances with defined resources. Time slicing shares execution time and does not provide the same memory and performance isolation. Neither mechanism causes separate GPUs to become a single transparent memory pool. GPU sharing also changes how utilization metrics should be interpreted.

[GPU Operator installation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/25.10/getting-started.html), [MIG management](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-operator-mig.html).

### 3.2 Dynamic Resource Allocation

DRA offers richer device selection and allocation than a resource count alone. Its core resources are native Kubernetes APIs:

| Resource | Responsibility |
|---|---|
| DeviceClass | Defines the class and selection criteria for claimable devices |
| ResourceSlice | Driver-published inventory and device attributes |
| ResourceClaim | A workload request for selected devices |
| ResourceClaimTemplate | Template for generating claims |

The core DRA API is stable in Kubernetes 1.34, while advanced sharing, partitioning and vendor integrations have separate version requirements. DRA does not automatically make an engine aware of distributed topology; claims and engine configuration must agree. For NVIDIA multi-node NVLink systems, vendor resources such as ComputeDomain can add another layer of allocation and fabric setup.

[DRA core API](https://v1-34.docs.kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/), [NVIDIA DRA integration](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/dra-intro-install.html).

### 3.3 Topology constraints matter at several scales

Within a node, consider GPU-to-GPU links, PCIe switches, CPU NUMA locality, GPU-to-NIC affinity and host memory. Between nodes, consider rack and fabric domains, latency and usable bandwidth. A placement of eight individually available GPUs can still be poor for a model if their interconnect is unsuitable.

For model parallelism, a practical topology to evaluate is TP within a fast GPU fabric and PP between nodes. Wide TP or EP can cross nodes when the hardware and model justify it. This is a starting experiment, not a rule that TP can never span nodes.

Network enablement can require RDMA device plugins or DRA, an appropriate CNI or secondary network, NCCL/UCX/libfabric configuration, shared memory sizing and compatible container drivers. Successful TCP connectivity does not prove that GPU transfers use the intended RDMA path.

[vLLM distributed strategies](https://docs.vllm.ai/en/latest/serving/parallelism_scaling/), [SGLang disaggregated networking](https://docs.sglang.io/docs/advanced_features/pd_disaggregation).

## 4 Quota admission and gang scheduling

### 4.1 Kueue controls admission and resource sharing

Kueue determines when a managed workload may consume quota. It is useful for multiple teams sharing scarce accelerators, choosing among GPU flavors, borrowing capacity, applying priorities and coordinating admission checks.

| Kueue resource | Role |
|---|---|
| LocalQueue | Namespaced submission and tenant grouping |
| ClusterQueue | Resource quota, flavor and sharing policy |
| ResourceFlavor | Characteristics of capacity, often tied to node labels and GPU type |
| Workload | Admission unit, normally created through the workload integration |
| WorkloadPriorityClass | Priority within Kueue admission/preemption |
| AdmissionCheck | External condition that must pass before admission |
| Topology | Hierarchical node topology for topology-aware admission/placement decisions |

Kueue is not required just to deploy a model. It becomes valuable when allocation policy is part of the problem. Its quota decision and topology-aware capabilities cooperate with a scheduler; they are not a replacement inference engine or request queue. Kueue documents serving integrations including LWS. Preemption policies suitable for batch work need particular care for a latency-sensitive service.

[Kueue concepts](https://kueue.sigs.k8s.io/v0.20/docs/concepts/), [ClusterQueue](https://kueue.sigs.k8s.io/docs/concepts/cluster_queue/), [LWS integration](https://kueue.sigs.k8s.io/docs/tasks/run/leaderworkerset/).

### 4.2 Gang scheduling options

| Option | Where it excels | What to account for |
|---|---|---|
| Native kube-scheduler Workload/PodGroup | Group-aware scheduling through upstream Kubernetes APIs | Kubernetes version, feature gates and workload-controller integration |
| Volcano | Batch/HPC/AI scheduling with queue policies, gang scheduling and topology features | Additional scheduler and its own resource model |
| scheduler-plugins coscheduling | Adding coscheduling through the scheduling framework | Plugin deployment/configuration and distinct PodGroup API |
| Kueue with compatible controllers | Quota-governed admission, optional topology awareness and readiness-based all-or-nothing handling | Admission/readiness recovery is different from one atomic binding transaction |
| Grove with its supported scheduler integration | Coordinated scheduling of heterogeneous inference component groups | Additional APIs and scheduler compatibility |
| Ray placement groups | Reserving logical Ray worker bundles for a distributed engine | Kubernetes must still supply the underlying pod/node capacity |

Gang scheduling means arranging sufficient cooperating workers. It does not mean every process becomes ready at the same instant, nor does it guarantee recovery after a rank fails. Pair group scheduling with a lifecycle controller and engine failure behavior.

[Volcano introduction](https://volcano.sh/docs/home/introduction/), [coscheduling plugin](https://github.com/kubernetes-sigs/scheduler-plugins/tree/master/pkg/coscheduling), [Grove](https://github.com/ai-dynamo/grove), [Ray cross-node placement](https://docs.ray.io/en/latest/serve/llm/user-guides/cross-node-parallelism.html).

## 5 Scaling replicas and scaling machines

### 5.1 What the scaling mechanisms actually scale

| Mechanism | Target | Signals | LLM-specific interpretation |
|---|---|---|---|
| HPA | Replicas of a scalable workload | CPU/memory or custom/external metrics | Can scale whole LWS groups when targeting its scale subresource |
| KEDA ScaledObject | A workload through HPA plus activation logic | Prometheus, queue depth, external services, CPU/memory and other scalers | Scales serving replicas or role groups; does not provision GPU nodes itself |
| KEDA ScaledJob | Number of finite Jobs | Queue/event triggers | Appropriate for offline inference tasks, not a replacement for a persistent serving Deployment |
| VPA | CPU/memory resource recommendations or updates | Historical container usage | Useful for CPU services; does not retune TP, model weights or GPU VRAM |
| Cluster Autoscaler | Preconfigured node groups | Unschedulable pods and consolidation decisions | Adds machines able to fit requested GPU workloads |
| Karpenter | Provider-supported node capacity | Pod requirements, NodePool policy, consolidation | Provisions suitable node shapes; cloud/provider capabilities vary |
| Serving-platform autoscaler | Engine replicas, role groups or runtime workers | Engine and router metrics | Must integrate with the workload and node layers |

[HPA](https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/), [workload autoscaling](https://kubernetes.io/docs/concepts/workloads/autoscaling/), [node autoscaling](https://kubernetes.io/docs/concepts/cluster-administration/node-autoscaling/), [KEDA concepts](https://keda.sh/docs/2.18/concepts/scaling-deployments/), [Karpenter NodePools](https://karpenter.sh/docs/concepts/nodepools/).

### 5.2 Metrics Server versus Prometheus

Metrics Server supplies standard CPU and memory resource metrics. It does not supply GPU utilization, KV occupancy, token backlog or time to first token by itself. KEDA's CPU/memory scalers use those standard resource metrics.

A common GPU-serving path is:

```text
vLLM/SGLang/router metrics ─┐
                          ├─ Prometheus or compatible query system
DCGM GPU telemetry ───────┘            │
                                     ▼
                             KEDA Prometheus scaler
                                     │
                                     ▼
                       HPA → Deployment/LWS/role scaler
                                     │
                                     ▼
                                Pending pods
                                     │
                                     ▼
                      Cluster Autoscaler or Karpenter
```

KEDA exposes external metrics to HPA; its metrics server is different from Kubernetes Metrics Server. Alternatively, a Prometheus Adapter can expose metrics to an ordinary HPA. KEDA's Prometheus scaler does not require an extra Prometheus Adapter. Prometheus is not mandatory if a supported cloud metric system, event source or external scaler provides the required signal.

[KEDA CPU metrics](https://keda.sh/docs/2.18/scalers/cpu/), [KEDA Prometheus scaler](https://keda.sh/docs/2.18/scalers/prometheus/), [DCGM Exporter](https://docs.nvidia.com/datacenter/dcgm/latest/gpu-telemetry/dcgm-exporter.html).

### 5.3 Which metrics should drive LLM scaling

The following are engineering guidance for choosing signals rather than universal thresholds:

| Signal | Useful interpretation | Limitation |
|---|---|---|
| Pending requests or queued tokens | Unserved demand and immediate pressure | Request count ignores differences in prompt/output lengths |
| Active sequences | Decode concurrency and occupancy | Per-sequence context length changes memory requirements |
| Input/output token rates | Workload intensity for prefill and decode | Needs calibration against a specific model/GPU setup |
| KV block occupancy and eviction/preemption | Memory pressure and cache churn | Some engines reserve large memory pools even when idle |
| TTFT and token latency | User-visible service objectives | Lagging signal; may trigger after latency is already poor |
| GPU compute/memory activity | Hardware behavior and diagnostics | High utilization can mean efficient batching; low compute can accompany bandwidth-bound decode |
| CPU and host RAM | Tokenization, API and cache-tier pressure | Weak proxy for model execution demand |

Treat each distributed replica as the scaling unit. Changing from TP4 to TP8 is generally a deployment/configuration change, not an ordinary HPA replica increase. In a disaggregated service, scale prefill and decode against their different bottlenecks. Use one active owner for each replica field so KEDA, a platform controller and a hand-written HPA do not fight.

Account for node startup, image download, model loading, collective initialization, compilation and cache warming. Scale-to-zero requires a request buffer/activator and a client latency budget. A metric emitted only by existing pods cannot by itself observe new demand once every serving pod is gone.

## 6 Distributed workload controllers

### 6.1 LeaderWorkerSet

`LeaderWorkerSet` treats one leader pod and its worker pods as a replica group. It provides identities, group-level rollouts, configurable group restart behavior and a scale subresource. It is suited to one model replica spanning several nodes and is usable with engines such as vLLM and SGLang.

For example, `replicas: 3` with group size two creates three groups, each with two pods. If each pod requests eight GPUs, the total is 48 GPUs; it is three serving replicas, not six independent replicas. The leader is normally also an engine rank, though the actual role depends on the launch configuration.

The current overview explicitly marks its gang-scheduling feature alpha. A stable-looking CRD version does not make every optional controller feature stable. LWS manages pod groups and lifecycle; the engine still supplies distributed initialization and TP/PP configuration.

[LWS overview](https://lws.sigs.k8s.io/stable/docs/overview/).

### 6.2 DisaggregatedSet

`DisaggregatedSet` sits above LWS and coordinates several roles, such as prefill, decode and encoder. Each role maps to child LeaderWorkerSets. It adds coordinated rollouts, draining and topology management across roles that would otherwise be separate workloads.

The useful distinction is group scaling versus role scaling. A distributed decode replica may itself need multiple pods. Adding another decode group is different from adding a rank inside that group. The project also documents `DisaggregatedSetRoleScaler` as a way to expose per-role scaling to HPA.

Use DS when cross-role lifecycle coordination is a requirement. Simple independent Deployments can also implement P/D separation, but they leave coordinated rollout and compatibility management to other components. Neither DS nor LWS transfers KV data itself.

[DS concepts](https://lws.sigs.k8s.io/stable/docs/concepts/disaggregatedset/), [role-scaling examples](https://lws.sigs.k8s.io/main/docs/examples/disaggregatedset/).

### 6.3 Grove

Grove addresses heterogeneous inference components with independent and coupled scaling. Its vocabulary includes PodClique for a role, PodCliqueScalingGroup for cliques that scale/schedule together, PodCliqueSet as the top-level composition, and PodGang as a scheduler-facing unit. This is particularly relevant to Dynamo deployments and hardware topology constraints.

Grove and DS/LWS overlap in lifecycle and grouping responsibilities, but their APIs and scheduler integrations differ. They are alternative building blocks for many deployments, rather than a requirement to install both underneath every service.

[Grove architecture and APIs](https://github.com/ai-dynamo/grove).

### 6.4 KubeRay and Ray Serve

KubeRay manages RayCluster, RayService and RayJob resources. RayService combines a Ray cluster with a long-running Serve application; RayJob handles finite work. Ray performs actor placement, resource management and execution within the cluster, including placement groups used by distributed inference engines.

There are multiple scaling loops: Serve scales model application replicas, the Ray autoscaler requests worker capacity, KubeRay reconciles pods, and a node autoscaler may supply machines. These loops must agree on resource bundles. Ray provides flexibility for composed Python inference graphs, but adds a runtime control plane and another failure domain to operate.

[KubeRay resources](https://docs.ray.io/en/latest/cluster/kubernetes/getting-started.html), [Ray production deployment](https://docs.ray.io/en/latest/serve/production-guide/index.html).

### 6.5 JobSet and training operators

JobSet groups Kubernetes Jobs and supplies distributed-job lifecycle and discovery. Kubeflow training operators expose resources such as TrainJob or older framework-specific jobs. They matter for training, evaluation, checkpoint transformations and batch inference, but do not provide the long-running request-routing and rollout semantics of an online model service. Argo Workflows can orchestrate preparation and batch stages without becoming the online inference scheduler.

[JobSet](https://jobset.sigs.k8s.io/docs/overview/).

## 7 Model serving platforms and where they excel

These products operate above some or all of the workload primitives. Several can use the same inference engine, and some integrate with one another.

| Platform | Main resources or packaging | Where it excels | Boundary or tradeoff |
|---|---|---|---|
| KServe | InferenceService, ServingRuntime, ClusterServingRuntime; LLMInferenceService and LLMInferenceServiceConfig for advanced LLM serving | A shared Kubernetes serving platform spanning predictive ML and generative AI; declarative model lifecycle | Runtime support differs between classic and advanced paths; assess their specific release matrices |
| llm-d | Composable router, endpoint picker, cache components and deployment guides; uses InferencePool and workload controllers | Kubernetes-native cache-aware routing, P/D disaggregation and distributed inference integration | A stack of components, not one universal model CRD; Helm chart names are not automatically resource kinds |
| NVIDIA Dynamo | DynamoGraphDeployment and DynamoGraphDeploymentRequest | Distributed inference graphs, KV-aware routing, P/D pools and backend-specific optimized recipes | Backend/hardware combinations and scheduling backends require validation |
| AIBrix | StormService and additional control-plane APIs; RayClusterFleet paths also documented | Model/adapter lifecycle, routing, GPU-aware optimization, distributed cache and multi-role inference | Custom control-plane model; native StormService and Ray-based deployment paths differ |
| vLLM production-stack | Helm deployment of engines, router and observability | A relatively direct Kubernetes reference stack around vLLM | Some advanced routing, autoscaling and disaggregation features are marked roadmap/WIP in the README |
| KubeRay with Ray Serve LLM | RayService and RayCluster | Programmable Python composition, multiple models and distributed worker orchestration | Adds Ray management and autoscaling alongside Kubernetes |
| KAITO | Workspace, InferenceSet; integration with InferencePool and node provisioning | Simplified model deployment with GPU sizing and infrastructure provisioning | Opinionated presets; current repository identifies vLLM as its supported engine |
| Seldon Core 2 | Model, Server, Pipeline, Experiment and related resources | Mixed ML portfolios, inference pipelines, model placement and experiments | General MLOps composition is its differentiator; distributed LLM KV behavior depends on the runtime/integration |
| BentoML and its deployment ecosystem | Python services, container packaging; Yatai is a Kubernetes operator project | Custom inference APIs and application pipelines around models | Packaging a service does not itself supply distributed engine semantics or Responses persistence |
| Plain Kubernetes | Deployment/StatefulSet/LWS plus your engine, Service and chosen autoscaler | Direct control, a small operational footprint, existing platform conventions | Your team assembles model lifecycle, cache routing and stateful API services |

Sources: [KServe architecture](https://kserve.github.io/website/docs/concepts/architecture), [llm-d](https://github.com/llm-d/llm-d), [Dynamo deployment API](https://github.com/ai-dynamo/dynamo/blob/main/docs/fern/pages/kubernetes/model-deployment/deploy-with-dgd.md), [AIBrix overview](https://aibrix.readthedocs.io/latest/getting_started/overview.html), [production-stack](https://github.com/vllm-project/production-stack), [Ray Serve LLM](https://docs.ray.io/en/latest/serve/llm/), [KAITO](https://github.com/kaito-project/kaito), [Seldon concepts](https://docs.seldon.ai/seldon-core-2/about/concepts), [BentoML](https://github.com/bentoml/BentoML), [Yatai](https://github.com/bentoml/yatai).

### 7.1 KServe and llm-d are related but distinct

KServe owns model-service configuration and reconciliation. llm-d supplies distributed inference components and deployment patterns. KServe's advanced LLM configuration can compose engine workloads, routing and scheduler components. You can also deploy llm-d components without using KServe as the top-level API.

KServe's current architecture recommends Standard mode for LLM serving; Knative mode remains an option with its own dependencies and scaling behavior. Do not assume KServe always requires a Knative installation. Also do not infer SGLang support for a specific LLMInferenceService template simply because a custom container can run under a broader serving resource.

[KServe architecture](https://kserve.github.io/website/docs/concepts/architecture), [LLM configuration composition](https://kserve.github.io/website/docs/next/model-serving/generative-inference/llmisvc/llmisvc-config-composition).

### 7.2 Dynamo separates a deployment graph from an intent request

DynamoGraphDeployment describes frontend and worker components, topology and configuration. DynamoGraphDeploymentRequest expresses a model, backend and optional workload/SLA targets; its planner/profiler generates a deployment configuration. They serve different levels of control. Explicit deployments are useful for reproducible tuned configurations; intent requests are useful for automated sizing and exploration.

Current documentation uses `nvidia.com/v1beta1`; older examples use a different v1alpha1 shape. Do not combine their fields. The node-provisioning, scheduler and transfer-library dependencies remain present even when one top-level object hides them.

[DGD guide](https://github.com/ai-dynamo/dynamo/blob/main/docs/fern/pages/kubernetes/model-deployment/deploy-with-dgd.md), [DGDR guide](https://github.com/ai-dynamo/dynamo/blob/main/docs/fern/pages/kubernetes/auto-deployment/auto-deploy-with-dgdr.md).

### 7.3 AIBrix provides another substantial control plane

AIBrix combines routing, autoscaling, cache management and model/adapter lifecycle. Its StormService supports multi-role orchestration, while documented RayClusterFleet paths use Ray for process placement. StormService can run without KubeRay, so Ray is not a universal prerequisite for AIBrix.

For organizations offering multiple models or LoRA adapters, its lifecycle and routing components are relevant beyond the narrow question of spreading one model over several GPUs. Confirm CRD groups against the chosen release because design proposals and installed schemas can differ.

[AIBrix overview](https://aibrix.readthedocs.io/latest/getting_started/overview.html), [multi-node paths](https://aibrix.readthedocs.io/latest/features/multi-node-inference.html).

## 8 Popularity and maturity signals

Popularity should be assessed within a layer. Volcano and KServe solve different problems; a higher star count does not make one a substitute for the other. Public repository interest also cannot reveal how many clusters run a particular optional CRD.

Rounded counts visible on the primary repository pages during this research:

| Project | GitHub stars approximately | Interpretation |
|---|---:|---|
| KServe | 6,200 | Substantial interest in a broad serving platform |
| Volcano | 6,100 | Substantial interest in batch/AI scheduling |
| llm-d | 5,200 | Substantial interest in distributed Kubernetes inference |
| AIBrix | 5,200 | Substantial interest in an LLM infrastructure control plane |
| Kueue | 3,100 | Established upstream ecosystem for admission and quota |
| KubeRay | 2,800 | Dedicated Kubernetes operator interest, separate from Ray's much larger overall ecosystem |
| vLLM Agentic API | 347 | Smaller specialized API-state project; assess maturity separately from engine popularity |

[KServe repository](https://github.com/kserve/kserve), [Volcano repository](https://github.com/volcano-sh/volcano), [llm-d repository](https://github.com/llm-d/llm-d), [AIBrix repository](https://github.com/vllm-project/aibrix), [Kueue repository](https://github.com/kubernetes-sigs/kueue), [KubeRay repository](https://github.com/kuberay-project/kuberay), [Agentic API repository](https://github.com/vllm-project/agentic-api).

For an actual selection exercise, add published adopters, support commitments, release cadence, upgrade history, conformance tests and end-to-end validation on your hardware. LWS and Gateway API Inference Extension are particularly important because other platforms compose them, even when the application team never creates their resources directly. New native scheduling APIs may have less field history than older external schedulers despite being upstream.

## 9 Inference engines and parallelism

### 9.1 Engine landscape

| Engine or server | Where it excels | Distribution and API considerations |
|---|---|---|
| vLLM | Broad model ecosystem, continuous batching, paged KV management and extensive platform integrations | TP/PP/DP and MoE-specific strategies; native Responses endpoint exists, but deployment-wide state is a separate concern |
| SGLang | Prefix reuse, structured generation, MoE serving and hierarchical KV management | TP/PP and model-specific distributed strategies; P/D transfer with Mooncake/NIXL; stateful gateway capabilities differ from worker capabilities |
| TensorRT-LLM | NVIDIA-specific kernels, inference optimizations and hardware tuning | Multi-GPU/distributed support and disaggregated recipes; model/hardware/version compatibility is central |
| Triton Inference Server | Multiple backend types, model ensembles and an existing NVIDIA inference estate | A server layer that can host a TensorRT-LLM backend; do not equate the server with the LLM execution engine |
| Hugging Face TGI | Existing Hugging Face serving deployments and integrations | Historically significant; the repository now states maintenance mode and recommends vLLM/SGLang or local alternatives going forward |
| LMDeploy | TurboMind/PyTorch inference, compression and supported LLM/VLM deployment | Evaluate its model and distributed features for the intended workload; OpenAI compatibility does not establish durable Conversations support |
| llama.cpp | Quantized GGUF models, CPU/GPU offload, edge and heterogeneous local hardware | Multi-device mechanisms exist; assess distributed throughput separately from datacenter TP/EP stacks |
| Xinference | Unified management of diverse text, embedding, speech and multimodal models | An umbrella serving system; engine/backend choice determines distribution and cache semantics |

Sources: [vLLM parallelism](https://docs.vllm.ai/en/latest/serving/parallelism_scaling/), [vLLM APIs](https://docs.vllm.ai/en/latest/serving/online_serving/), [SGLang](https://github.com/sgl-project/sglang), [TensorRT-LLM](https://github.com/NVIDIA/TensorRT-LLM), [Triton](https://github.com/triton-inference-server/server), [TGI maintenance notice](https://github.com/huggingface/text-generation-inference), [LMDeploy](https://github.com/InternLM/lmdeploy), [llama.cpp](https://github.com/ggml-org/llama.cpp), [Xinference](https://github.com/xorbitsai/inference).

Ollama and LocalAI also belong in a broader catalog for local deployment and compatible APIs. Their ease of installation is a different selection axis from coordinated multi-node P/D inference. They should not be assumed to satisfy the distributed serving and durable Responses contract merely because a client can use an OpenAI-style SDK. [Ollama](https://github.com/ollama/ollama), [LocalAI](https://github.com/mudler/LocalAI).

### 9.2 What the parallelism modes mean

| Strategy | What is divided or replicated | Why use it | Main cost |
|---|---|---|---|
| Tensor parallelism | Tensor operations/weight partitions within layers | Fit large weights and accelerate execution across GPUs | Frequent collectives and interconnect sensitivity |
| Pipeline parallelism | Consecutive model layers across stages | Fit layers across devices/nodes | Stage imbalance, activation transfer and pipeline scheduling |
| Data parallelism | Independent inference capacity, often full model replicas | Increase throughput and availability | Additional weight copies and potentially fragmented caches |
| Expert parallelism | MoE experts across workers | Serve large sparse models efficiently | All-to-all communication and expert load imbalance |
| Context parallelism | Long-context attention work/state across ranks | Handle very long sequences and attention pressure | Specialized communication and model/backend restrictions |
| P/D disaggregation | Prefill and decode execution pools | Tune prompt ingestion and token generation independently | KV transfer, coordination and extra capacity |

These modes compose. A decode role may use TP8 across one node; another may use TP8×PP2 across two nodes. P/D separation is not equivalent to placing early layers on prefill and later layers on decode. Both phases execute the model, usually with model weights available in both pools.

[vLLM scaling guide](https://docs.vllm.ai/en/latest/serving/parallelism_scaling/), [SGLang P/D design](https://docs.sglang.io/docs/advanced_features/pd_disaggregation).

### 9.3 Capacity examples

Illustrative configurations, not benchmark results:

| Scenario | Engine layout | Kubernetes layout | GPU count |
|---|---|---|---:|
| One small-model instance | TP1 | One pod requesting one GPU | 1 |
| Four independent instances | Four TP1 replicas | Deployment with four replicas | 4 |
| One larger instance | TP4 | One pod requesting four GPUs on one node | 4 |
| Three TP4 instances | Three model replicas | Three four-GPU pods, with placement policy as needed | 12 |
| One model across two eight-GPU nodes | TP8×PP2 | LWS group with two eight-GPU pods | 16 |
| Two copies of the preceding model | Two distributed replicas | Two LWS groups of two pods each | 32 |
| Separate prompt and generation pools | Two TP4 prefill replicas and four TP4 decode replicas | Two role pools under DS, Dynamo, StormService or an equivalent composition | 24 |

The product TP×PP gives the GPU count for the illustrated dense-model replica only; EP/DP/context layouts need their own accounting. GPUs within one distributed replica are a cooperating team. A load balancer must route to the replica's request endpoint, not arbitrarily to an internal rank.

## 10 Model artifacts and memory budgeting

Model checkpoint distribution and model execution distribution are different tasks. A shared PVC, object-store downloader, local NVMe cache or image-contained artifact supplies checkpoint files. The engine then loads its partitions according to the parallel configuration. A storage cache does not shard computation.

Artifact planning should include immutable model revisions, tokenizer and chat-template versions, adapter compatibility, credentials, storage throughput and concurrent restarts. A fleet that downloads the same large checkpoint at once can overload the model store. Container images that include all weights simplify provenance but can be very large; startup downloads keep images smaller but require an effective cache and readiness policy.

GPU memory has several consumers: weights, KV blocks, activations, runtime workspaces, communication buffers and compilation/CUDA-graph allocations. An estimate based only on parameter count is insufficient. Weight quantization and KV quantization are separate decisions with different accuracy and compatibility implications.

For a conventional transformer KV layout, an illustrative unsharded estimate is:

```text
KV bytes ≈ 2 × layers × KV heads × head dimension
             × cached tokens × concurrent sequences × bytes per element
```

For 80 layers, eight KV heads, head dimension 128 and BF16, this is 327,680 bytes per token, or 320 KiB. At 32,768 tokens, one sequence is about 10 GiB before sharing and overhead. Ten such distinct sequences are about 100 GiB. This arithmetic is an example, not a claim about a particular model. GQA/MQA, latent attention, sliding windows, hybrid state-space models, quantization, prefix sharing and parallel replication/sharding change the actual allocation.

[vLLM Kubernetes model storage example](https://docs.vllm.ai/en/latest/deployment/k8s/), [Dynamo checkpoint deployment](https://github.com/ai-dynamo/dynamo/blob/main/recipes/README.md), [LMCache model compatibility](https://docs.lmcache.ai/getting_started/compatibility.html).

## 11 KV cache systems and the different kinds of memory

### 11.1 Cache types that should be kept separate

| State or cache | Contents | Typical location | What losing it means |
|---|---|---|---|
| Checkpoint cache | Model files | PVC, object store, local NVMe | Slower restart/download |
| Active KV cache | Attention tensors for running sequences | GPU HBM, partitioned according to engine layout | Active request interruption or engine-specific recomputation |
| Prefix cache | Reusable tensors for matching input prefixes | GPU and optional other tiers | More prompt computation |
| External KV cache | Offloaded/shared tensor blocks | Host RAM, SSD or remote store | More recomputation or transfer, depending on policy |
| Conversation history | Messages, tool calls/results, response lineage | Database/object storage | Loss of durable conversational context if no other copy exists |
| Semantic response cache | Previously generated answers and matching metadata | Gateway cache/vector store | Fewer answer-cache hits |
| Long-term application memory | Facts, summaries and retrieved context | Application database/vector store | Loss of selected cross-session knowledge |

A conversation ID identifies API state. A KV cache key identifies tensors for a particular model and input representation. Sticky routing can improve reuse but cannot turn GPU memory into durable history. A semantic answer cache also does not supply model KV tensors.

### 11.2 Cache and transfer options

| Component | Primary role | Where it excels | What it does not replace |
|---|---|---|---|
| vLLM native KV/prefix management | Allocate GPU KV blocks and reuse matching prefixes | Engine-local reuse with minimal extra infrastructure | A durable conversation store |
| SGLang RadixAttention and HiCache | Prefix reuse and hierarchical KV tiers | Repeated prefixes, multi-turn/agent traffic and configured offload | Conversation item authorization and persistence |
| LMCache | Extract, store, retrieve and share/offload KV through engine connectors | Extending reuse beyond one engine's GPU-resident cache | A model deployment controller or generic cross-model cache |
| Mooncake | KV-centric serving components, transfer engine and distributed storage | P/D transfer and distributed cache architectures | The Kubernetes admission layer |
| NIXL | Transfer abstraction across memory/storage and transport backends | Moving inference data efficiently without hard-wiring one transport | A complete standalone conversation or KV lifecycle service |
| Dynamo router/cache components | Cache-aware worker choice and configured memory-tier integration | Coordinating reuse and P/D execution in Dynamo graphs | The inference backend and durable API history |
| llm-d cache components | Cache-state indexing, placement decisions, offload/P2P integration | Reuse across a Kubernetes inference pool | The backend's tensor computation |
| AIBrix KV infrastructure | Distributed cache management alongside its serving control plane | Cache-aware fleet infrastructure | API conversation semantics |

Sources: [llm-d cache architecture](https://llm-d.ai/docs/dev/architecture), [SGLang feature documentation](https://docs.sglang.io/docs/advanced_features/pd_disaggregation), [LMCache compatibility](https://docs.lmcache.ai/getting_started/compatibility.html), [Mooncake](https://github.com/kvcache-ai/Mooncake), [NIXL](https://github.com/ai-dynamo/nixl), [Dynamo router](https://github.com/ai-dynamo/dynamo/blob/main/docs/fern/pages/developer-guide/knowledge-base/modular-components/router/router-guide.md), [AIBrix](https://aibrix.readthedocs.io/latest/getting_started/overview.html).

### 11.3 Routing affinity and transferring cache are different

A cache-aware router can send a request to the worker that already has its prefix. No tensor transfer is necessary in that case. An external cache connector can instead load tensors into a different worker. P/D disaggregation transfers prefill output to decode so generation can continue. An installation may use one or all three mechanisms.

Cache reuse requires compatible model revision, tokenization, position handling, attention layout, dtype and adapter identity. Different TP layouts may require explicitly supported redistribution. Do not assume arbitrary tensors can move among vLLM, SGLang and TensorRT-LLM just because a common transfer library is installed.

Capacity and latency depend on the slowest tier used. Host RAM and SSD increase reusable capacity but are not equivalent to HBM for active decode. A shared remote tier also introduces bandwidth, metadata and failure dependencies. Tenant cache namespaces and model-version invalidation are part of the design.

## 12 Inference routing and gateway resources

### 12.1 Gateway API and the inference extension

Gateway API resources describe network entry points and routes. GatewayClass selects an implementation; Gateway instantiates a listener/configuration; HTTPRoute describes matching and forwarding. These are installed APIs backed by a gateway controller, not features that operate without a proxy implementation.

Gateway API Inference Extension adds the InferencePool abstraction and endpoint-picker integration. The gateway consults an EPP to choose an appropriate serving endpoint using metrics and capabilities. The pool selects backends; it does not create or scale their GPU pods. Older examples involving InferenceModel should be checked against the installed extension release rather than treated as a current universal requirement.

An ordinary Kubernetes Service is still useful for discovery and connectivity. Its standard balancing does not understand prefix-cache locations, queued tokens or LoRA residency. Those decisions belong in an inference router or gateway extension.

[Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/), [Gateway API concepts](https://gateway-api.sigs.k8s.io/concepts/api-overview/).

### 12.2 Routing options by responsibility

| Component | Primary decision | Fit |
|---|---|---|
| llm-d router/EPP | Select an endpoint from a model pool using load/cache policy | Kubernetes inference pools and composable gateway integrations |
| Dynamo router | Choose workers using cache/load and P/D execution cost | Dynamo inference graphs |
| SGLang Model Gateway | Route to regular or P/D workers, with additional API/history capabilities | SGLang-oriented deployment with an integrated router tier |
| AIBrix gateway | Model-aware fleet routing and configured cache-aware policies | AIBrix-managed services |
| production-stack router | Model aliases, discovery and configured routing | Direct vLLM reference deployment; check WIP features |
| vLLM Semantic Router | Choose a model/policy based on request semantics | Model selection above replica selection |
| API gateways | Identity, quotas, policy, provider mapping and failover | Shared organization-facing access |

Model selection and replica selection can compose: a semantic router selects a model, then an inference router selects a replica of that model. Avoid redundant layers with unclear retry, timeout and accounting ownership.

[llm-d](https://llm-d.ai/docs/dev/architecture), [Dynamo routing](https://github.com/ai-dynamo/dynamo/blob/main/docs/fern/pages/developer-guide/knowledge-base/modular-components/router/router-guide.md), [SGLang Model Gateway](https://docs.sglang.io/docs/advanced_features/sgl_model_gateway), [production-stack routing](https://github.com/vllm-project/production-stack), [Semantic Router with AIBrix](https://vllm-sr.ai/docs/installation/k8s/aibrix/).

## 13 Responses APIs and durable conversation state

### 13.1 Define the contract before comparing products

For this platform, a complete conversation contract should separately specify:

1. `POST /v1/responses` request/response shapes, tool items and streaming events.
2. Stored response lookup, deletion and retention.
3. `previous_response_id` continuation and branching.
4. A durable conversation ID and conversation-item create/read/update/delete behavior.
5. Cross-replica access and survival of API/worker restarts.
6. Tenant/user authorization, deletion, retention and audit rules.
7. Compaction, maximum context handling and optional long-term memory.
8. Background execution/cancellation and tool execution, if required.

These capabilities are not interchangeable. A response chain is not the same API object as a conversation; a trace `session_id` may only group logs; and storing every message does not make an unbounded history fit the model context. API compatibility needs operation-level tests.

### 13.2 Stateful API services and general gateways

| Option | What current sources establish | Where it excels | Remaining integration decision |
|---|---|---|---|
| vLLM Agentic API | Stored Responses, response continuation, Conversations/items endpoints; SQLite and PostgreSQL persistence | Explicit stateful Responses layer over self-hosted inference | Smaller project; pin supported upstream/runtime and use shared storage for HA |
| SGLang Model Gateway | Responses and Conversations endpoints with history connectors including PostgreSQL, Oracle and Redis | Combining model routing and history ownership at a gateway tier | Verify transport, worker mode, tools and P/D combinations in the intended release |
| LiteLLM | Responses API and provider normalization; bridged history resolution when configured; native pass-through relies on backend state | Many providers, centralized model access, routing and accounting | Do not infer complete Conversations CRUD from Responses support; choose state ownership explicitly |
| Kong AI Gateway | Responses routes, provider transformations and gateway policy | Existing enterprise API gateway estates | Proxied provider persistence is different from gateway-owned storage for a local stateless backend |
| Agent Router formerly Envoy AI Gateway | Gateway/inference-pool integration, provider routing, quotas and observability | Kubernetes Gateway API and inference-aware traffic policy | Add or verify a separate history owner; reviewed capabilities do not establish a durable local Conversations service |
| agentgateway | AI-agent/MCP proxy and LLM traffic infrastructure | Agent connectivity and policy alongside model access | Validate Responses operations and persistence separately |
| Portkey | Multi-provider routing, observability, guardrails and answer caching | Managed or self-hosted access/governance depending on edition | Answer caching and logging are not evidence of a durable local conversation contract |
| Bifrost | Multi-provider gateway, virtual keys/budgets, failover and semantic caching | A gateway with Go integration and configurable plugins | Verify exact Responses/Conversations and shared-history behavior rather than assuming it from compatibility claims |
| Higress | AI-native API gateway and extension ecosystem | Existing Envoy/Wasm gateway deployments | Verify exact API translation and history ownership for the selected plugin |
| Application-owned Responses facade | Whatever API/state contract the application implements | Complete control over identity, retention and backend portability | Highest implementation and compatibility-test burden |

Sources: [Agentic API](https://github.com/vllm-project/agentic-api), [Agentic API reference](https://vllm-project.github.io/agentic-api/docs/latest/api/index), [SGLang Model Gateway](https://docs.sglang.io/docs/advanced_features/sgl_model_gateway), [LiteLLM Responses](https://docs.litellm.ai/docs/response_api), [LiteLLM native/bridged behavior](https://docs.litellm.ai/docs/response_api_native_passthrough), [Kong](https://developer.konghq.com/plugins/ai-proxy-advanced/), [Agent Router](https://theagentrouter.ai/docs/capabilities/), [agentgateway](https://github.com/agentgateway/agentgateway), [Portkey](https://github.com/Portkey-AI/gateway), [Bifrost](https://github.com/maximhq/bifrost), [Higress](https://github.com/higress-group/higress).

Rows with a persistence verification requirement are not claims that the product lacks the feature. They identify where routing/caching claims are insufficient to establish your complete stateful API requirement. Product editions can also differ.

### 13.3 Two concrete compatibility boundaries

LiteLLM documents that native passthrough forwards `previous_response_id` to the backend. A backend that does not store responses rejects it. For supported bridged configurations, `store_prompts_in_spend_logs: true` allows LiteLLM to resolve history and send an expanded request. The provider adapter is therefore an architectural choice, not just a name.

SGLang documents foreground Responses generation through its HTTP P/D router, but explicitly excludes worker-local persisted response history, `previous_response_id`, retrieval-by-ID and background history workflows under that mode. P/D workers run in separate processes and their local stores cannot supply coherent shared history. Router-level history connectors are a distinct capability; test the complete chosen routing path instead of combining feature lists from unrelated modes.

[LiteLLM state behavior](https://docs.litellm.ai/docs/response_api_native_passthrough), [SGLang HTTP P/D limitations](https://docs.sglang.io/docs/advanced_features/pd_disaggregation).

The llm-d stateful Responses reference deployment places Agentic API and PostgreSQL in front of the inference router. It reconstructs prior turns, then sends a self-contained inference request to the model pool. Its documented reference configuration validates vLLM; newer Agentic API integrations may cover additional upstreams, but that does not broaden the tested llm-d recipe automatically.

[llm-d stateful Responses reference](https://llm-d.ai/docs/dev/well-lit-paths/foundations/serve-responses-api).

## 14 How a request moves through the assembled system

Consider a two-node model replica, with a stateful API tier and prefix-aware routing:

1. A client submits a new input with a conversation ID or a previous response ID.
2. The external gateway authenticates the client and checks access, quotas and model policy.
3. The stateful API service verifies ownership, loads prior items and constructs the model context. It may compact history or select retrieved memory.
4. The inference router selects a healthy replica, balancing queue pressure against prefix reuse. The endpoint represents the whole distributed model team.
5. The engine tokenizes/formats the prompt and identifies reusable KV. Missing prefix blocks are computed or loaded through a configured connector.
6. TP/PP/EP ranks execute their portions. In a P/D service, prefill produces KV, transfer machinery moves it, and decode generates tokens.
7. The stream returns through the API service and gateway. Tool execution can create additional inference rounds, each with explicit state and accounting.
8. The API service persists response items and lineage according to its consistency policy. GPU KV may remain for reuse, but history must remain recoverable after cache eviction.

Controllers operate beside this request path. They create and restart workers, admit capacity, scale replica groups and provision nodes. They should not need to contact the Kubernetes API for every generated token.

## 15 Deployment options by GPU topology and use case

The following are architectural options, not a product shortlist. Each row can expose the same Responses contract if its API-state layer is designed consistently.

| Use case | Workload shape | Platform options | Cache/API considerations |
|---|---|---|---|
| Single GPU, one endpoint | One engine pod | Plain Deployment; production-stack; KServe; KAITO; AIBrix; RayService | Local prefix reuse may suffice; use shared history for durable conversation IDs |
| Several GPUs serving independent small models | One or more single-GPU pods per model | KServe, AIBrix, production-stack, Ray Serve, plain Kubernetes | Model routing and per-model quotas; MIG/sharing only after isolation/capacity assessment |
| One model needing multiple GPUs in one node | One TP/PP engine replica per multi-GPU pod | Plain Deployment, KServe, Dynamo, AIBrix, KAITO or Ray Serve | GPU topology and KV head partitioning matter; no multi-pod gang is needed for that one pod |
| Many copies of a multi-GPU model | Multiple whole replica pods/groups | Same model platforms with HPA/KEDA or their autoscaler | Scale whole replicas; prefix-aware routing becomes more valuable |
| One model spanning multiple nodes | Several coordinated engine-rank pods | LWS directly or through a serving platform; RayCluster/RayService; Grove/Dynamo; StormService | Gang/topology placement, distributed readiness, rank failure recovery and fast interconnect |
| Large MoE across a fabric | EP plus model-specific DP/TP composition | SGLang/vLLM/TensorRT-LLM with llm-d, Dynamo, Ray or compatible controller | Expert communication, load imbalance and supported parallel layout dominate |
| Separate prefill and decode | Independently scalable roles, each possibly multi-node | DS/LWS, Dynamo/Grove, AIBrix StormService, Ray Serve or explicit role workloads | KV transfer, role ratio, revision compatibility and API-store location |
| Long-context conversations or repeated tool loops | Stable prefixes and increasing history | Any suitable model platform with cache-aware routing and optional external KV | Shared history plus compaction; evaluate LMCache/HiCache/Mooncake or platform cache integration |
| Offline generation/batch inference | Finite queued tasks | Jobs/JobSet/RayJob, Kueue or Volcano; engine batch mode | KEDA ScaledJob can dispatch workers; online conversation API often unnecessary |
| Multi-tenant shared accelerator estate | Quota-governed serving and batch capacity | Kueue admission or appropriate scheduler queue system plus chosen serving platforms | Separate admission quota from request quotas; avoid preempting critical live services casually |
| Mixed classical ML and LLM applications | Multiple runtimes and processing stages | KServe, Seldon, Ray Serve, BentoML | Pipelines and lifecycle standardization may outweigh maximum LLM-specific specialization |
| Edge or small on-premise deployment | Small node count and varied hardware | llama.cpp, Ollama, LocalAI, supported vLLM/SGLang hardware paths | Simpler packaging; validate API fidelity and distribution separately |

### 15.1 Composable stack families

**Direct Kubernetes stack.** GPU enablement → optional node provisioner → Deployment or LWS → vLLM/SGLang → model-aware router → stateful API tier → optional organization gateway. This exposes component choices and gives the platform team assembly responsibility.

**Kubernetes serving platform stack.** GPU enablement → optional Kueue → KServe or AIBrix → managed workloads and inference routing → engine → conversation service. This standardizes model deployment and policy while retaining engine and API-state choices.

**Dynamo stack.** GPU/fabric enablement → supported scheduling infrastructure → DGD/DGDR → frontend/router and workers → backend engine → configured transfer/cache components → stateful API tier. This makes the distributed inference graph a primary management unit.

**Ray stack.** GPU/node provisioning → KubeRay → RayService → Serve application replicas and placement groups → engine → stateful API tier. This is useful when inference is one component of a larger Python service graph.

**Integrated SGLang gateway stack.** Suitable workload controller → SGLang regular or disaggregated workers → Model Gateway → shared history backend → optional external policy gateway. API/history support must be verified for the selected gateway mode and release.

Kueue and cluster autoscaling are optional in these families when quota contention or dynamic machine provisioning is absent. On a fixed bare-metal cluster, autoscaling can add replicas only while suitable free capacity exists; provisioning more nodes requires an actual machine-provisioning integration.

## 16 Ownership and integration rules

| Responsibility | Choose an explicit owner | Avoid |
|---|---|---|
| Model definition | Serving platform or GitOps-managed workload | Competing controllers rewriting engine flags |
| Replica count | HPA/KEDA, serving autoscaler or a documented combination | Two independent controllers writing the same scale field |
| Multi-pod lifecycle | LWS, Grove, StormService, Ray or another compatible controller | Treating rank pods as independent disposable service replicas |
| Gang and placement policy | Compatible scheduler plus admission integration | Mixing unrelated PodGroup APIs |
| Node provisioning | One coordinated provisioner strategy per capacity pool | Assuming KEDA creates physical GPU capacity |
| KV metadata and transfers | Engine/cache/router integration with versioned contracts | Treating NIXL installation as a complete KV service |
| Conversation persistence | Gateway/API service or application database | Depending on random worker-local response stores |
| Request retries and tools | Explicit gateway/API/application policy | Duplicate tool side effects after automatic replay |
| Model/context identity | Versioned model, tokenizer, template and adapter configuration | Reusing incompatible cached tensors |

A high-level resource should own its generated children. For example, if DS controls role LWS resources, use its supported role-scaling mechanism rather than patching generated resources arbitrarily. If a platform manages an HPA, configure that integration rather than adding an unrelated HPA against the same target.

## 17 Reliability and end to end validation

The validation matrix should test the complete deployment combination, including model revision, engine version, GPU type, driver/runtime, controller version, network transfer path, router and state-store schema.

| Test | Expected property |
|---|---|
| Kill a worker rank in a multi-node replica | The group recovers according to policy, and unhealthy ranks do not receive new traffic |
| Make one required node unavailable | Partial startup is bounded; no indefinite GPU reservation deadlock |
| Increase demand while the cluster is full | Admission, replica scaling and node provisioning expose clear pending states |
| Roll model/adapter version during traffic | Routing and cache identity prevent incompatible revision mixing |
| Drain a decode worker with active streams | Existing requests finish or fail with defined semantics; new traffic stops |
| Evict every reusable KV block | New turns still reconstruct history; only performance changes |
| Restart the API pod and send the next turn to another replica | Conversation and response IDs still resolve through the shared store |
| Submit two turns concurrently to one conversation | Ordering, branching or conflict behavior is deterministic |
| Retry a tool-bearing request after a stream failure | Tool side effects and stored items are not silently duplicated |
| Delete a conversation | Defined history/object retention is enforced; cache deletion is treated separately |
| Switch user or tenant while reusing an ID | Access is denied unless explicitly authorized |
| Test long prompts, output limits and cancellation | Memory pressure and cleanup remain controlled |
| Benchmark cold and warm prefixes | Report TTFT, token latency, throughput and cache behavior separately |
| Disable the expected RDMA path | Diagnostics distinguish fallback transport from the intended fast path |

Measure GPU-seconds per successful request or generated token alongside throughput and latency. Report input/output lengths, concurrency, cache-hit conditions, quantization and errors so that framework comparisons are meaningful. A single tokens-per-second number cannot establish which system excels for every use case.

## 18 Resource inventory for architecture discussions

This inventory is organized by responsibility rather than installation order. Exact API versions depend on the selected release.

| Family | Important resources | Built in or installed |
|---|---|---|
| Core workloads | Pod, Deployment, StatefulSet, DaemonSet, Job, CronJob | Built in |
| Discovery and storage | Service, EndpointSlice, PVC, PV, StorageClass, Secret, ConfigMap | Built in |
| Core policies | ResourceQuota, LimitRange, PriorityClass, PodDisruptionBudget, NetworkPolicy | Built in |
| Native grouped scheduling | Workload, PodGroup; newer composite features separately gated | Native versioned APIs with feature requirements |
| DRA | DeviceClass, ResourceSlice, ResourceClaim, ResourceClaimTemplate | Native versioned APIs with driver requirements |
| Workload scaling | HorizontalPodAutoscaler | Built in |
| Vertical scaling | VerticalPodAutoscaler | Installed CRD/controller |
| Event scaling | ScaledObject, ScaledJob, TriggerAuthentication, ClusterTriggerAuthentication | KEDA CRDs |
| Node provisioning | NodePool, NodeClaim, provider NodeClass | Karpenter CRDs; Cluster Autoscaler uses provider node groups instead |
| Admission | LocalQueue, ClusterQueue, ResourceFlavor, Workload, AdmissionCheck, WorkloadPriorityClass, Topology | Kueue CRDs; optional APIs vary by version |
| External batch scheduling | Queue, PodGroup, Volcano Job | Volcano APIs |
| Distributed serving lifecycle | LeaderWorkerSet, DisaggregatedSet, DisaggregatedSetRoleScaler | LWS project CRDs |
| Distributed component groups | PodCliqueSet, PodClique, PodCliqueScalingGroup; PodGang scheduler API | Grove and its scheduler integration |
| Distributed runtime | RayCluster, RayService, RayJob | KubeRay CRDs |
| Distributed finite work | JobSet | JobSet CRD |
| General model serving | InferenceService, ServingRuntime, ClusterServingRuntime | KServe CRDs |
| Advanced LLM serving | LLMInferenceService, LLMInferenceServiceConfig | KServe CRDs |
| Inference graphs | DynamoGraphDeployment, DynamoGraphDeploymentRequest | Dynamo CRDs |
| AIBrix orchestration | StormService; RayClusterFleet and other optional components | AIBrix CRDs; check release schemas |
| Simplified model provisioning | Workspace, InferenceSet, RAGEngine | KAITO CRDs |
| General ML pipelines | Model, Server, Pipeline, Experiment | Seldon Core 2 CRDs |
| Gateway configuration | GatewayClass, Gateway, HTTPRoute, ReferenceGrant | Gateway API CRDs |
| Inference routing | InferencePool | Gateway API Inference Extension CRD |
| Prometheus integration | Prometheus, ServiceMonitor, PodMonitor, PrometheusRule | Optional Prometheus Operator CRDs |

Prometheus can also run without Prometheus Operator, and a managed compatible metrics service can replace the local server. Installing ServiceMonitor objects only works when a controller consumes them. Similarly, the existence of a CRD says that the API can store a configuration; its controller and data-plane dependencies must also be installed and healthy.

## 19 Questions that determine which options fit

To provide options for a particular use case, collect the following inputs before choosing a platform:

- Model architecture, revision, parameter count, precision and supported engine implementations.
- GPU model/count per node, topology and available network fabric.
- Whether the objective is fitting one model, increasing throughput, reducing TTFT, supporting long context, or sharing a fleet among teams.
- Input/output token distributions, active concurrency, prefix repetition and latency objectives.
- Whether services are always on, bursty, offline or preemptible.
- Whether model weights and KV both fit, rather than weights alone.
- Required API operations, durable conversation identity, tools, streaming, cancellation and retention.
- Existing commitments to Ray, KServe, a gateway, cloud provisioning or an observability system.
- Operational willingness to run extra schedulers, cache services, databases and custom controllers.

Those inputs determine a composition of components. A single-GPU service can use the same conversation API as a multi-node MoE service, while their worker controllers, placement rules and KV transfer mechanisms differ substantially.
