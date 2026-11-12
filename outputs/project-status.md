<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Project status

Next architecture under design: generated infrastructure and model bundles with separate Terraform states, stable retained-pool identity, one shared DevOps project per platform and independently replaceable model releases. Schemas are generated with editable defaults; artifact run IDs belong only in filenames under fixed model/region/shape folders. This split/publisher is not implemented yet. See docs/platform-model-lifecycles.md and docs/generated-deployment-bundles.md. The source described below still uses a combined deployment root.

The repository has two working Resource Manager stack configurations: live model/GPU discovery, followed by a selected deployment into an existing regional OKE cluster. Deployment now defaults to a read-only OCI preview, with dynamic RMS compartment/cluster controls, derived image/network/NSG details and a discovery-carried CPU budget. GPU inference and DevOps runtime execution have not been validated on allocated hardware.

Discovery takes a Hugging Face URL/ID, revision, context and concurrency. It reads model metadata and the live recipe API, pins upstream source/image evidence and scans READY OCI subscriptions. Only choices with positive physical capacity and quantity-confirmed GPU headroom are selectable; zero/unknown/insufficient observations stay in diagnostics. Untested serving settings are labelled separately from capacity eligibility.

There is no static models/engines catalog, model dropdown, catalog generator/policy or compatibility selection helper. Live alias metadata identifies the parent recipe source and recommended variant. RMS consumes a compact per-selection handoff (measured UTF-8 budget <=8000 bytes), with authenticated Object Storage fallback for larger payloads; the full report remains available for local/audit use. Deployment consumes that JSON and an existing cluster; it retains the selected image, flags, topology, workload and provenance. Explicit overrides require the corresponding assessment/expert checks.

Runtime assets are module-owned: OCI CLI/JQ under oci-discovery, GPU specs under accelerator-inventory, and deployment/benchmark scripts plus Helm/chart/router, LeaderWorkerSet and CPU benchmark defaults under devops-serving. Root scripts/ contains packaging tools only; tests/ contains development checks. GPU Operator/RDMA plugin installs and pins have been removed. Deployment records OKE add-on versions and checks actual node capabilities, reusing existing cluster support. Required OKE add-ons and RDMA network configuration must already be enabled/configured; the stack does not change their lifecycle.

Both RMS ZIPs place main.tf/schema.yaml at the archive root with modules/. make check-packages extracts, initializes and validates the delivered artifacts. The GitHub Package RMS stacks workflow builds and uploads direct ZIP artifacts on main pushes/merges; hosted execution awaits a remote push.

Verification for the preview/handoff feature: 27 script/render checks; 92 native tests across deployment, target/image discovery, handoff, runtime metadata, planner, allocation, DevOps and discovery, including a saved-report-to-preview contract with cloud resources mocked. The real OCI image selector also passed a read-only Ashburn lookup. Earlier model-profile/resolver tests and real RMS discovery Plan evidence remain recorded in the implementation plan. No GPU allocation or DevOps execution was performed. Latest local compact handoffs are indexed in work/rms-handoffs/index.json; their original scan timestamps are preserved, with no capacity refresh implied.

Remaining work includes actual GPU allocation/inference/benchmarking, automatic multi-node suggestions, cache companion integration, independent GGUF config/tokenizer staging, broader modality tests and durable Responses conversation storage. No current report or mock pass establishes those capabilities.

Obsolete research copies/logs/reports and the unused provider version were removed. Active provider cache, Terraform state and inputs, current artifacts and user research notes were preserved. See docs/repository-layout.md for ownership and docs/rms-discovery.md for package usage.

The deployment preview resolves OKE-supported images using exact Kubernetes/OS/architecture and shape metadata. A live native image lookup for BM.GPU.A10.4 in Ashburn succeeded without instances. Public container CUDA manifest/config inspection is optional during preview and required before provisioning; its local live blob lookup encountered a CDN TLS trust failure (verification was not disabled). Actual driver/kernel compatibility remains pending. See docs/deployment-preview.md for the minimal RMS flow and limitations.
