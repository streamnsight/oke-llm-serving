<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Configured model bundles and platform access

Discovery publishes an infrastructure ZIP per confirmed option. Each ZIP includes the selected model specification, the infrastructure implementation, and the model-only template/module closure once. Infrastructure Apply creates the platform resources and then publishes a configured model ZIP into the **original discovery bundle bucket**, using that bucket's recorded region. This publication bucket is neither pipeline evidence storage nor model weight storage.

The model ZIP contains `main.tf` at its root, runtime-only modules, `inputs/model-spec.json`, `inputs/platform-binding.json`, schema defaults and matching Terraform variable defaults. It excludes the infrastructure implementation and publishers. No nested Terraform execution is used: the native archive resource writes the ZIP at Apply, so RMS Plan and Apply can use different workers.

`model_launch_url` opens the model stack wizard in the GPU cluster's region. The PAR points to one short launch-copy object to remain within the Console's ZipOrigin limit; a descriptive copy lives under `models/<owner--model>/<region>/<shape>/model-<timestamp>-<run>-<selection>.zip`. Only the filename contains run identity. The classic Object Storage endpoint is used because it was validated with the RMS importer. Links expire; reapplying regenerates the publication and can revoke older links. Do not treat a historical launch link as permanent storage.

## The two input documents

`model-spec.json` freezes the model identity/revision, structured Hub profile/workload assumptions, **complete selected option**, exact recipe arguments/environment and provenance. A fallback serving resolution is retained for analytical options without their own recipe rendering. It is not the all-region discovery report and is not a large Console variable.

`platform-binding.json` contains references to resources owned elsewhere:

| Binding | Meaning |
| --- | --- |
| Platform name/generation, component generations/modes/versions | Desired shared capabilities; not proof that their pipelines succeeded |
| Cluster OCID, compartment, region and Kubernetes version | The existing cluster the model must target |
| Project, OKE deployment environment, source/results repositories | Existing DevOps foundation; the model state does not manage these resources |
| Runner subnet/NSGs | Existing private API access and outbound connectivity |
| GPU pool OCID, allocation identity/selector, host/GPU geometry and transport | Retained capacity to reuse; no new-capacity search or node-pool ownership |
| Boot/storage budget and CPU shape selector | Declared bounds to check against actual allocatable resources |
| Model storage descriptor | Direct Hub source or retained staged snapshot/manifest; CPU staging scratch is not a serving volume |
| Trusted onboarding pipeline and owner token | How exact model principals receive namespace access |

Small editable settings are defaults in **both** `schema.yaml` and Terraform declarations. No generated tfvars file overrides the user's edits. The full selected specification remains immutable provenance; effective overrides must be recorded and validated. Changing image, model, parallelism or context does not inherit the original fit/compatibility claim automatically.

The model stack creates its own uniquely named pipelines/artifact references in the existing project. It must not declare/import GPU pools, Compute Clusters, projects, shared add-ons/controllers or the platform's repositories. It must not grant itself `CLUSTER_MANAGE` or cluster-admin.

## CPU-only development and real GPU deployment

With the temporary infrastructure debug switch, the binding has a null GPU pool and `gpu_allocation_enabled=false`. The model ZIP and pipeline resources can still be created, rendered and inspected. This does not make them ready to serve: runtime preflight must refuse a missing allocation or insufficient free devices. Creating the RMS stack never automatically starts a model deployment pipeline.

GPU runtime tests remain deferred. CPU/mock tests verify configuration, publication and lifecycle controls, not model loading, CUDA/kernel compatibility, placement, NCCL/RDMA/NIXL, KV-cache correctness or throughput. Live model deployment must verify current allocation identity, actual schedulable free resources, image/model identity, storage fit and required served APIs/controllers before creating serving workloads.

## Trusted namespace onboarding

After model stack Apply, copy its `onboarding_arguments` into the platform's `model_onboarding_pipeline_id` pipeline parameters. The arguments are `MODEL_NAMESPACE` and `MODEL_PIPELINE_IDS`, a small JSON array of exact pipeline OCIDs. The default `MODEL_ACCESS_OPERATION` is `grant`. The namespace must start with `<platform>-model-`.

The trusted platform script checks every pipeline is active in the exact project and declares the requested `MODEL_NAMESPACE` default **before any Kubernetes mutation**. It creates only a dedicated namespace and fixed, code-defined RBAC/service-account resources. It never accepts an arbitrary manifest, allocates GPUs, deploys models or installs controllers. Existing namespaces/RBAC require matching platform owner, cluster and namespace annotations; foreign resources are refused. Concurrent onboarding is serialized with a namespace lease. An orphaned lease requires inspection of the old execution before explicit recovery; it is never silently stolen.

Namespace ownership is explicit:

```text
label oke-llm/platform-owner = first 32 hex characters of SHA256("<platform>/<cluster OCID>")
label oke-llm/model-namespace = true
annotations: oke-llm/model-namespace, oke-llm/platform-name, oke-llm/cluster-id
```

Model principals receive namespace-only workload/config/PVC/Helm-release permissions, selected namespaced LWS/DAS/monitoring/scaling/route instances, plus read-only node/API/CRD discovery. In shared component namespaces, additional Roles permit only `get` on exact controller Deployment names and, for managed components, their exact ownership/readiness ConfigMaps. This trusted context is an immutable artifact, not a user-selected arbitrary namespace/name list. They cannot mutate namespaces, nodes, cluster RBAC, CRDs or shared controllers. The fixed `oke-llm-router` service account gets only pod/service/endpoint discovery within that namespace. The trusted platform principal retains the elevated permissions required to establish these bindings; they are not inherited by the model pipelines.

For local CLI use after model stack Apply, an arguments file can be generated without shell-substituting command text:

```sh
terraform output -json onboarding_arguments | jq '{items: to_entries | map({name: .key, value: .value})}' > onboarding-arguments.json
oci devops deployment create-pipeline-deployment \
  --pipeline-id <trusted-platform-onboarding-pipeline-ocid> \
  --deployment-arguments file://onboarding-arguments.json
```

An onboarding success proves access setup only. Run model preflight/validation separately. User token values never belong in these arguments; a Hugging Face credential input is an existing namespace Secret reference or an explicitly supported secret integration.

## Retained storage and removal

Direct downloads require the full selected snapshot per engine cache/node unless a separately validated storage loader avoids replication. The default boot budget accounts for two snapshot copies for **every packed engine Pod per host**, plus 100 GiB for OS/images/working space (minimum 200 GiB). The matching model workspace is a per-Pod estimate; actual kubelet reservations and allocatable/free disk must still be checked. These are estimates, not an instruction to resize a retained pool. An unsuitable retained pool needs a different storage choice or explicit infrastructure maintenance.

Object Storage staging does not produce a usable POSIX directory automatically. Its descriptor identifies a completed snapshot; the model adapter must materialize and verify it into an appropriate retained serving PVC/local cache. The CPU stager's RWO scratch claim must never be mounted as a shared GPU model volume. Until a supported materialization path exists, `staged_object_storage` is an explicit deployment block rather than a silent fallback to Hub downloads. See [model storage](model-storage.md).

Removal order is deliberate: run model retire to remove/drain owned workload releases, run trusted onboarding with `MODEL_ACCESS_OPERATION=revoke` for the exact principals, then destroy model Terraform metadata. Revocation refuses active Pods. Keep pipeline resources until revoke succeeds because onboarding verifies their OCI identities. Namespace, shared read-only Role, router account, retained PVCs and model data are not purged by access revocation. Shared infrastructure/controllers and GPU hosts remain untouched. Data/namespace cleanup is a separate owner-reviewed lifecycle.

Source artifacts use model-specific paths in the existing repository; two Terraform states must not manage the same repository/path/version resource. Reports are immutable Generic Artifacts with execution identities. The original discovery bundle bucket must remain available while configured launch links are needed; cross-state model publication objects are not owned by the discovery state's object list.
