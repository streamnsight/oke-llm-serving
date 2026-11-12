<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Project status

The repository has two working Resource Manager stack configurations: live model/GPU discovery, followed by a selected deployment into an existing regional OKE cluster. GPU inference and DevOps runtime execution have not been validated on allocated hardware.

Discovery takes a Hugging Face URL/ID, revision, context and concurrency. It reads model metadata and the live recipe API, pins upstream source/image evidence and scans READY OCI subscriptions. Only choices with positive physical capacity and quantity-confirmed GPU headroom are selectable; zero/unknown/insufficient observations stay in diagnostics. Untested serving settings are labelled separately from capacity eligibility.

There is no static models/engines catalog, model dropdown, catalog generator/policy or compatibility selection helper. Live alias metadata identifies the parent recipe source and recommended variant. Deployment consumes the discovery JSON plus selection ID and target infrastructure; it retains the selected image, flags, topology, workload and provenance. Explicit overrides require the corresponding assessment/expert checks.

Runtime assets are module-owned: OCI CLI/JQ under oci-discovery, GPU specs under accelerator-inventory, and deployment/benchmark scripts plus Helm/chart/router, LeaderWorkerSet and CPU benchmark defaults under devops-serving. Root scripts/ contains packaging tools only; tests/ contains development checks. GPU Operator/RDMA plugin installs and pins have been removed. Deployment records OKE add-on versions and checks actual node capabilities, reusing existing cluster support. Required OKE add-ons and RDMA network configuration must already be enabled/configured; the stack does not change their lifecycle.

Both RMS ZIPs place main.tf/schema.yaml at the archive root with modules/. make check-packages extracts, initializes and validates the delivered artifacts. The GitHub Package RMS stacks workflow builds and uploads direct ZIP artifacts on main pushes/merges; hosted execution awaits a remote push.

Verification: 24 script/render checks, including managed GPU/RDMA capability detection; 10 allocation tests covering OKE add-on version inventory; 10 profile, 10 resolver, 32 planner, six discovery-root and 14 deployment-root native tests; both extracted-package validations; a successful real RMS Plan using module-owned assets/live metadata; and deployment planning from that actual JSON with cloud resources mocked. Latest private artifacts are work/latest-discovery-plan.json and work/deployment-inputs.tfvars.json.

Remaining work includes actual GPU allocation/inference/benchmarking, automatic multi-node suggestions, cache companion integration, independent GGUF config/tokenizer staging, broader modality tests and durable Responses conversation storage. No current report or mock pass establishes those capabilities.

Obsolete research copies/logs/reports and the unused provider version were removed. Active provider cache, Terraform state and inputs, current artifacts and user research notes were preserved. See docs/repository-layout.md for ownership and docs/rms-discovery.md for package usage.
