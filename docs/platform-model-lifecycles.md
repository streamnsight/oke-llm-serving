<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Infrastructure and model lifecycles

Discovery, infrastructure and each model deployment have separate Terraform states. Discovery publishes both configured child stacks up front; a model project does not depend on infrastructure Apply outputs. See [the binding contract](model-binding.md) for runtime authorization and [the workflow](deployment-workflow.md) for execution order.

| Owner | Responsibilities |
|---|---|
| Discovery | Model/recipe/workload assessment, confirmed regional capacity options, configured ZIPs, Object Storage/PAR publication and one linked HTML report |
| Infrastructure/platform | Retained GPU pool and supported Compute Cluster placement, OKE add-on assessment, shared controllers/CRDs, platform DevOps project and component/onboarding pipelines; reuse existing CPU pools |
| Each model project | Independent DevOps project, environment, artifact repositories, model pipeline identities and deploy/validate/benchmark/undeploy pipelines; namespaced model workload/router/scaling resources at execution |

Infrastructure allocation labels remain stable across models and discovery runs. Shared controllers have one platform owner in a cluster. Additional models reuse them rather than creating duplicate releases. Creating several infrastructure stacks is not an automatic shared-controller or allocation-adoption mechanism; review existing ownership before applying another platform stack.

## Cluster selection and deferred readiness

A configured model stack requires the cluster ID. Native OCI data resolves VCN, runner subnet/NSGs, Kubernetes version and a unique compatible managed GPU pool. Optional advanced overrides resolve genuine ambiguity or a pool in another compartment. A unique same-shape retained pool can be reused in another AD of the region; its actual placement is recorded.

Creating project/pipeline metadata works before a GPU pool exists. Pipeline execution later resolves the live managed pool, instance-to-node membership and trusted controller readiness. Kubernetes GPU requests and bounded rollout decide actual placement; preflight does not claim total allocatable GPUs are free. Models never create, resize, cycle or delete GPU hosts.

## Shared components and model instances

Infrastructure assesses and reuses OKE-managed GPU/network add-ons. Missing mandatory native prerequisites block allocation; automatic add-on configuration is still incomplete. Avoid duplicate NVIDIA operators/device plugins. Shared optional services use independent component pipelines: Prometheus defaults on, KEDA is opt-in and LWS follows the selected topology.

| Infrastructure capability | Model-owned resource |
|---|---|
| LWS controller and CRD | Namespaced LeaderWorkerSet instance |
| KEDA controller/CRDs and metrics service | Model ScaledObject/HPA and trigger |
| Prometheus/operator installation | Model monitoring resources where supported |
| Optional shared gateway controller | Model route/backend resources, or a model-owned router |
| Optional shared cache/storage service | Explicit compatible model cache allocation/connector/workers |

A vLLM operator is optional. Controller installation belongs to the platform, while custom-resource instances belong to models. Recipe companion flags do not provision their services. LMCache backends, P-D/Ray adapters and durable conversation storage require explicit integration; unsupported configurations block rather than silently losing recipe requirements. See [component support](model-layer-components.md).

## Authorization and artifacts

Each model owns its project, pipelines, environments, source/results repositories and OCIR chart repository. The trusted platform onboarding pipeline validates the model's exact active project/pipeline identities and namespace before granting Kubernetes permissions. Model runners cannot bootstrap their own cluster administration. Older deployed platform onboarding software must be updated for independent project identities.

Kubernetes access is namespace-scoped for writes, with bounded read-only node/API/controller/context access. Generic Artifact IAM is currently compartment-scoped, so independent projects alone do not provide artifact isolation between differently trusted models. Separate compartments and reviewed policies are needed for that boundary.

Scripts, specifications, chart values and runtime evidence use Generic Artifacts; charts use OCIR. Object Storage holds discovery reports/bundles and optionally retained staged model files. Optional CPU staging has separately bootstrapped RBAC and retained scratch storage; it does not yet materialize a verified serving volume automatically.

## Retirement

Run the guarded model undeploy pipeline, revoke its namespace access with the trusted onboarding flow, then destroy its Terraform metadata. Destroying pipeline definitions alone does not uninstall an executed Helm release. Namespaces, retained PVC/model data, shared controllers and GPU pools survive model retirement. A recreated project has a new identity and cannot silently adopt a predecessor's retained namespace.

Shared-component uninstall is a separate platform operation with dependent-model checks. GPU pools and Compute Clusters retain destroy protection. The temporary infrastructure `skip_gpu_allocation` debug switch suppresses only allocation resources; never enable it after allocating retained GPU hosts.

Live metadata creation and local/mock runtime checks do not prove CUDA/NCCL/RDMA, inference, cache reuse or performance. Those require later authorized hardware validation.
