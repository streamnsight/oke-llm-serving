<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Repository layout and asset ownership

| Location | Purpose |
|---|---|
| `terraform/stacks/discovery` | Model/workload inputs and cross-region assessment |
| `terraform/stacks/deployment` | Selected configuration, retained GPU infrastructure and DevOps resources |
| `terraform/modules/oci-discovery/scripts` | Runtime OCI CLI/Bash lookup and its JQ library |
| `terraform/modules/accelerator-inventory/data/gpus.json` | Shared GPU memory, topology and hardware mapping, owned by inventory |
| `terraform/modules/serving-resolution` | Live recipe JSON source/alias lookup, immutable upstream YAML and engine image assessment |
| `terraform/modules/devops-serving/scripts` | Runtime deployment runner, Kubernetes renderer and official vLLM benchmark wrapper |
| `terraform/modules/devops-serving/data/components.json` | Deployment infrastructure versions and image digests |
| `scripts` | ZIP packaging and extracted-package validation only |
| `tests` | Development-only script, renderer and schema checks |
| `work` | Ignored inputs, handoff/reports, package outputs and active local caches |

Static models/engines catalogs, the model-list policy, model-catalog refresh tool and legacy selection helper have been removed. A user supplies a Hugging Face URL/ID. The live recipe endpoint includes its source repository/path/SHA and recommended variant, including alias endpoints such as Flint NVFP4. Missing upstream metadata remains explicit; there is no old catalog compatibility fallback.

Only GPU specifications and deployment infrastructure defaults remain as module-owned data files. `components.json` contains Helm/chart/router, LeaderWorkerSet and CPU benchmark versions. GPU/network support comes from the existing OKE-managed add-ons and node image; the stack inventories their versions instead of pinning or installing another GPU Operator or RDMA plugin. See [OKE-managed GPU/network prerequisites](oke-managed-addons.md). Recipe JSON supplies the model's serving image and launch settings.

Each RMS ZIP contains root Terraform files and a `modules/` directory holding its runtime assets. Root build tools and development tests are not shipped. Packaging only rewrites stack-to-module references; module-owned asset references remain relative to the module itself or its sibling owner.

Node/YAML is a development-test dependency only. Runtime discovery uses Terraform HTTP/external providers with module-owned OCI CLI/Bash/JQ scripts; the benchmark pipeline uses the pinned CPU vLLM tooling image.
