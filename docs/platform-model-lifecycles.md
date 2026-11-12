<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Proposed infrastructure and model lifecycles

Status: design proposal, 2026-11-12. The current implementation still has a combined deployment root. This proposal separates retained GPU infrastructure from model releases; no infrastructure has been created or changed for this design work.

## Recommended boundaries

Use three stack types with separate Terraform states: discovery, infrastructure/platform, and model deployment. Splitting files or child modules inside one state would not establish the required lifecycle separation.

| Owner | Responsibilities |
|---|---|
| Discovery | Model/recipe/workload assessment, new-capacity or existing-pool suitability, generated bundles, publication objects/PARs and launch URLs |
| Infrastructure/platform | Existing-cluster binding, retained GPU and CPU pools, supported RDMA Compute Clusters, cluster add-on configuration, shared CRDs/controllers and optional metrics/autoscaling services; shared DevOps project, notification/logging/evidence foundation and platform bootstrap pipelines |
| Model deployment | A model instance's namespace/release, vLLM engine groups, LWS or other orchestration **instances**, router/routes, per-model LMCache services/configuration, metrics/scaling objects and deploy/validate/benchmark/retire pipelines |

Infrastructure allocation identity and node labels must be stable platform/pool identifiers, independent of a model name, model SHA or discovery run ID. The current allocation/control labels and model runner use the same `name`; those bindings must be separated. A model targets an allocation selector supplied by the platform, while its workload labels identify the model instance.

Start with one infrastructure/platform owner per existing cluster, managing its retained pool allocations. Shared controllers, CRDs and the shared project have one owner even when several pools/models use them. Check for an existing platform owner before proposing a new one. Additional allocations in that cluster must reuse that owner rather than create duplicate controller releases. Keep platform services and pool allocation as separate internal modules so a future explicit platform-versus-allocation stack split remains possible without changing the model contract.

## OKE add-ons and Kubernetes resources

Infrastructure discovers and reuses OKE-managed add-ons first. It enables/configures required missing optional add-ons through OKE where supported. Existing add-ons already owned by another administrator/stack are reused unless ownership is explicitly transferred; discovery must not silently adopt them into a second Terraform state. Avoid duplicate NVIDIA GPU Plugin/Operator installations or independent RDMA device plugins. [OKE add-on management](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengintroducingclusteraddons.htm).

Shared custom components use the infrastructure bootstrap pipeline: for example LeaderWorkerSet controllers/CRDs, Prometheus and KEDA when those capabilities are selected. A single-GPU model does not imply installing every scheduler/operator. New model requirements can request a platform capability update; a model pipeline does not install or upgrade cluster-wide controllers itself.

The ownership distinction applies to controller APIs and their instances:

| Infrastructure installs/configures | Model creates/configures |
|---|---|
| LeaderWorkerSet controller and CRD | A namespaced LeaderWorkerSet for its model |
| KEDA controller/CRDs and shared metrics capability | Its ScaledObject/HPA and model-specific trigger/query |
| Shared Prometheus/operator installation | Its ServiceMonitor/PodMonitor/rules where supported |
| Shared gateway/ingress controllers, if enabled | Its route/backend/inference-pool resources, or its own serving router |
| Shared cache/storage backend, if selected | Its cache allocation, connector, namespace and model-specific workers |

Check actual chart output for cluster-scoped resources/RBAC and handle them through the platform owner. Namespace-specific model installations must not uninstall shared releases. LMCache keys/data must remain compatible with model revision, dtype and KV layout; sharing infrastructure does not make caches interchangeable between models. Initial autoscaling targets model replicas within retained GPU capacity, not GPU node scale-down.

Infrastructure CPU sizing follows the enabled shared services plus declared workload/benchmark headroom. The current lightweight CPU estimate cannot be reused blindly after adding Prometheus, KEDA, shared caches or several concurrent model jobs. Model deployment reports insufficient CPU/GPU resources rather than modifying infrastructure pools from another state.

## One shared DevOps project

Infrastructure owns or explicitly reuses one DevOps project for the platform, including its notification topic, logging setup and shared evidence-storage foundation. Model stacks receive its `project_id` and create their own uniquely named pipelines/stages/artifact references inside it. They do not declare/import the same project as a managed resource.

OCI projects group pipeline/artifact/environment resources, so sharing the project does not require sharing one mutable model pipeline. See [DevOps projects](https://docs.oracle.com/en-us/iaas/Content/devops/using/devops_projects.htm) and [project creation/logging requirements](https://docs.oracle.com/en-us/iaas/Content/devops/using/create_project.htm).

Keep bootstrap and model identities separate. Platform bootstrap manages approved cluster-wide components. Model principals receive the namespace/runtime and evidence-prefix access they need. Initial cluster RBAC authorization belongs to platform bootstrap/administrator setup. Each model owns its pipeline identities/policies/bindings, so adding or removing one model does not rewrite another model's pipeline list or privileges. Serialize deploy/retire operations for the same model instance and retain immutable per-release specifications/evidence.

A shared `project_id` alone does not authorize Kubernetes access. Infrastructure must provide an approved namespace/onboarding step for new model principals, after the trusted infrastructure pipeline has been bootstrapped by an authorized cluster administrator. Model pipelines must not grant themselves cluster-admin to install shared components.

## Small platform contract

Infrastructure publishes a versioned platform/allocation descriptor with cluster/region, stable platform/pool IDs and selectors, GPU shape/count/topology, CPU/storage bounds, runner subnet/NSGs, shared `project_id`, evidence location and supported controller/API capabilities. It contains no credentials and is not a full Terraform state dump.

Keep desired platform specification and runtime readiness separate. Terraform can own `platform-spec.json`; the bootstrap pipeline writes readiness evidence for that specification generation after checking the actual nodes/controllers. Both must refer to the same generation/hash. Do not have Terraform and the pipeline repeatedly overwrite the same status object. Models check readiness, required capabilities and actual allocation geometry before deployment.

A model ZIP can embed a binding or reference a small authenticated profile URI. The deployment still checks live cluster/pool identity and capabilities to detect stale bindings. This avoids a large RMS input and avoids coupling model access to the entire infrastructure state.

## User flow

For new capacity: discovery publishes an infrastructure launch URL. The user selects an existing regional OKE cluster; VCN, compatible images and unambiguous subnets/NSGs are derived. Only ambiguous networking or explicit overrides require more input. Preview remains the default. Once explicitly provisioned, infrastructure/bootstrap establishes the platform and can emit a model launch URL already bound to the actual pool/project/profile. The model stack then needs no repeated cluster/network definition.

For a subsequent model: discovery assesses it against an existing platform/allocation profile and emits a model bundle targeting that pool. Only allocate additional hosts if the user separately chooses infrastructure expansion.

New allocation and reuse are different eligibility paths. An existing compatible pool can be usable when OCI reports zero spare hosts or zero additional GPU headroom: its hosts are already allocated. Reuse checks per-node GPU/memory/topology, actual free schedulable resources or an explicit replacement of the current model, disk/cache capacity, driver/runtime compatibility and shared capabilities. It must not be rejected by the current **new-capacity** candidate filter. Expanding the pool still requires fresh quantity-specific entitlement and physical capacity checks.

Initial reuse can support sequential model replacement or separate free allocations. Concurrent models in one pool additionally need admission/resource coordination; a preflight observation is not a reservation. Do not count all advertised allocatable GPUs as free while another model is using them.

## Generated defaults and selected specification

The publisher creates each final `schema.yaml` from a base schema template plus that option's resolved recommendations. It also creates matching Terraform declaration defaults from the same small recommendation map. The user does not edit the schema manually; RMS shows prefilled, editable scalar settings and optional expert controls. Values edited by the user must win over recommendations in the HCL resolver.

The full all-region discovery report is not required in either deployment bundle. Retain it once as a discovery audit artifact. Infrastructure gets a selected `infrastructure-spec.json`; model deployment gets a selected `model-spec.json` plus its platform binding. These hold complex launch/cache/orchestration settings, workload assumptions and source identity/hashes without turning them into giant Console variables. Small editable recommendations are translated to schema/HCL defaults. Preserve baseline versus effective values for provenance and revalidate changes; do not keep a stale memory-fit result after tuning topology/context.

## Retire a model without retiring its pool

Provide a model-retire/uninstall pipeline that removes the model's owned workloads/routes/scaling resources, waits for requested GPUs to be released, and handles cache/PVC retention explicitly. Then the model's Terraform pipeline/IAM metadata can be removed. The current imperative DevOps runner means Terraform destruction of pipeline resources alone does not uninstall Helm/Kubernetes workloads.

Model retirement must not remove node pools, Compute Clusters, managed add-ons, shared CRDs/controllers, the project or another model's resources. Switching orchestration type must also clean up obsolete owned workload objects so old LWS groups do not keep consuming GPUs.

Infrastructure retirement is a separate explicit procedure with model dependency checks. Keep retained-pool safeguards, review image/Kubernetes/shape updates and control cycling: Terraform `prevent_destroy` alone does not prevent every service-side rolling replacement or in-place operation from releasing hosts. A model change has no authority to trigger those changes.

## Phases and tests

1. [ ] Define platform/allocation versus model specifications, stable identities, ownership and ready-generation contract; keep only selected configuration in bundles.
2. [ ] Split current allocation/platform/project creation from per-model pipelines/resources into distinct roots/states. Preserve managed-addon reuse; enable missing required managed capabilities through the infrastructure owner.
3. [ ] Move shared controller installation out of the model runner. Add model retire/replace behavior, per-model identities, shared-project references and namespace ownership tests.
4. [ ] Generate infrastructure/model schemas and defaults from templates, plus bound model links after infrastructure identification. Put timestamp/run/option IDs only in ZIP filenames under the fixed model/region/shape folder.
5. [ ] Test new allocation versus existing-pool eligibility, including zero regional spare capacity with a usable retained pool; busy GPUs, topology/storage/driver mismatch and missing platform capability must be explicit.
6. [ ] Verify model plans/destroy paths cannot manage infrastructure resources, shared-project ownership is unique, and retiring/replacing one model leaves pools/controllers/other models intact. Validate extracted bundles and authenticated RMS flows in preview. No live GPU creation/resizing/deletion during this design/prototype validation.
