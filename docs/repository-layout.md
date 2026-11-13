<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Repository layout and asset ownership

Discovery is the repository root and the single released entry ZIP. Reusable modules and downstream templates have the same paths in source and package. The infrastructure publisher renders/uploads confirmed options and defines object-read PAR launch links. The combined deployment template is retained for development while the model-only split is pending. Live OCI publication/RMS validation remains pending.

| Location | Purpose |
|---|---|
| `.` | Model/workload inputs and cross-region assessment |
| `templates/infrastructure` | GPU-only retained pools and a shared-controller bootstrap pipeline; reuses existing CPU pools |
| `templates/deployment` | Selected configuration, retained GPU infrastructure and DevOps resources |
| `modules/oci-discovery/scripts` | Runtime OCI CLI/Bash lookup and its JQ library |
| `modules/accelerator-inventory/data/gpus.json` | Shared GPU memory, topology and hardware mapping, owned by inventory |
| `modules/serving-resolution` | Live recipe JSON source/alias lookup, immutable upstream YAML and engine image assessment |
| `modules/devops-serving/scripts` | Runtime deployment runner, Kubernetes renderer and official vLLM benchmark wrapper |
| `modules/devops-serving/data/components.json` | Deployment infrastructure versions and image digests |
| `modules/platform-bootstrap` | Shared platform DevOps foundation, LWS chart/client defaults, node readiness and bootstrap scripts |
| `modules/infrastructure-publisher` | Native Apply-time infrastructure ZIPs, private bucket/objects, expiring PARs and launch URLs |
| `modules/deployment-target` | Read-only cluster, network/NSG and regional image resolution |
| `modules/oke-node-image` | Native OKE image/version/shape selector |
| `modules/deployment-handoff` | Byte-budgeted per-selection RMS payloads |
| `modules/control-plane-sizing` | CPU component budget shared by discovery/deployment |
| `modules/serving-image-metadata` | Digest-verified public vLLM CUDA metadata |
| `scripts` | ZIP packaging and extracted-package validation only |
| `tests` | Development-only script, renderer and schema checks |
| `work` | Ignored inputs, handoff/reports, package outputs and active local caches |

Static models/engines catalogs, the model-list policy, model-catalog refresh tool and legacy selection helper have been removed. A user supplies a Hugging Face URL/ID. The live recipe endpoint includes its source repository/path/SHA and recommended variant, including alias endpoints such as Flint NVFP4. Missing upstream metadata remains explicit; there is no old catalog compatibility fallback.

Only GPU specifications and deployment infrastructure defaults remain as module-owned data files. `components.json` contains Helm/chart/router, LeaderWorkerSet and CPU benchmark versions. GPU/network support comes from the existing OKE-managed add-ons and node image; the stack inventories their versions instead of pinning or installing another GPU Operator or RDMA plugin. See [OKE-managed GPU/network prerequisites](oke-managed-addons.md). Recipe JSON supplies the model's serving image and launch settings.

Each RMS ZIP contains root Terraform files and a `modules/` directory holding its runtime assets. Root build tools and development tests are not shipped. Packaging only rewrites stack-to-module references; module-owned asset references remain relative to the module itself or its sibling owner.

Local discovery state/tfvars/cache moved with its configuration to the repository root without changing their bytes. The previous private discovery work directory is preserved as `work/discovery-local/` to avoid colliding with root work files. Downstream and example caches/state moved with their directories. Run `terraform init` after the move to refresh cached module paths; do not initialize a second infrastructure state for an already allocated pool.

Node/YAML is a development-test dependency only. Runtime discovery uses Terraform HTTP/external providers with module-owned OCI CLI/Bash/JQ scripts; the benchmark pipeline uses the pinned CPU vLLM tooling image.
