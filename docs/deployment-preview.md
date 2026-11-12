<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Deployment preview and compact RMS handoff

Deployment defaults to `provision_resources = false`. A Plan reads model and OCI metadata and outputs the expected infrastructure without allocating GPU/CPU nodes, Compute Clusters, policies, buckets or DevOps resources. Applying this preview only saves outputs and the Terraform-local specification validation record. It does not run a DevOps pipeline. Use a new deployment stack/state for this flow; do not turn provisioning off again on an already allocated state. Existing retained-pool destruction safeguards still apply.

## Minimal RMS flow

1. Run discovery with the model URL/ID, context and concurrency. Choose a capacity-confirmed configuration in the report. Capacity is a timestamped observation, not a reservation.
2. Create the deployment RMS stack in that configuration's region. Paste `deployment_handoffs[ID].inline_json` into **Discovery JSON**. A compact payload contains one choice, so a second selection ID is unnecessary.
3. Select the existing OKE cluster from the dynamic picker. The compartment defaults to RMS's injected `compartment_ocid`; the deployment name defaults to `llm-serving`. Leave resource creation disabled.
4. Run Plan and inspect `deployment_preview`. Resolve any `target.issues` before considering provisioning. A resolved input set does not establish CUDA, network-fabric or inference readiness.

The stack derives the cluster VCN, Kubernetes version and existing node-pool networking. When there is one matching worker subnet for the selected AD, it reuses it for GPU/CPU nodes and the DevOps runner. Native-CNI pod subnets and existing NSGs are reused too. Regional subnets work across ADs; incompatible AD-specific subnets are excluded. Ambiguous subnet/NSG policies remain explicit issues rather than arbitrary choices. Advanced dynamic VCN/subnet/NSG pickers provide overrides; overrides must match the cluster VCN. Sharing the API subnet is not required, and sharing a VCN alone does not prove routing, DNS, security-rule or HTTPS-egress access.

## Image and resource defaults

Automatic image lookup reads the regional OKE node-pool sources, matches Oracle Linux major version (default 8), GPU/CPU architecture and the exact cluster Kubernetes version, then reads image timestamps and supported shapes. It chooses the newest AVAILABLE compatible image. It does not fall back to another Kubernetes version or an unoptimized platform image when no match exists. Image OCID overrides are optional and still undergo shape/metadata checks; custom images outside OKE's source list require their own Kubernetes/bootstrap validation. Preview outputs expose the exact IDs for review and optional freezing as overrides.

This follows the native lookup pattern in [oke-langfuse's node-image-selector](https://github.com/streamnsight/oke-langfuse/tree/main/modules/oke/node-image-selector), with per-image shape checks. Oracle documents the required [OKE image/version naming and compatibility](https://docs.oracle.com/en-us/iaas/Content/ContEng/Reference/contengimagesshapes.htm).

Discovery carries a component CPU estimate: one `VM.Standard.E4.Flex` node with 4 OCPUs and 24 GiB. Its budget includes the router, controllers, one CPU benchmark job and system headroom. This is a single-node baseline, not HA or a measured request-throughput recommendation. More components, simultaneous benchmark jobs or HA require reassessment. Older local reports fall back to this same estimate. Advanced CPU overrides must meet the budget. GPU boot storage defaults to at least 200 GiB and grows with the full checkpoint download estimate plus cache/OS headroom.

Benchmark tuning is hidden from the normal RMS form. Defaults are 50 requests, at most 1024 input tokens and 128 output tokens, reduced when needed to fit the configured context with a template allowance. Explicit Terraform overrides are checked for fit. The benchmark remains a separately triggered DevOps pipeline. Its run parameters `BENCHMARK_REQUESTS`, `BENCHMARK_INPUT_TOKENS` and `BENCHMARK_OUTPUT_TOKENS` override defaults for that run without repackaging; values are read as JSON data and checked before starting the benchmark job.

RDMA is inferred from the selected configuration. Provisioning creates the retained Compute Cluster/placement when required. Existing OKE-managed GPU/network support remains the cluster's responsibility. RDMA resource names are detected on actual nodes after allocation; existing Multus attachment overrides are advanced settings, not normal form questions. See [OKE-managed prerequisites](oke-managed-addons.md).

## CUDA/driver boundary

The host CUDA toolkit version is not the container runtime version. Before provisioning, the stack reads the pinned public vLLM image's manifest/config, verifies both content digests, and reports `CUDA_VERSION`, `NVIDIA_REQUIRE_CUDA` and the documented minor-compatibility driver floor when available. Custom registries remain explicitly unknown. This registry/CDN read is optional during preview (`inspect_serving_image = true`) and automatic when provisioning is enabled. TLS is verified; network/trust failures are not silently accepted.

OCI image metadata does not establish the running NVIDIA driver version or GPU kernel behavior. The driver floor is a preliminary bound; PTX/JIT and model-specific kernels may require newer drivers. CUDA initialization, actual kernels, model inference and RDMA/NCCL still require validation on retained GPU nodes. No driver/operator version upgrade is inferred just from the serving version. See [NVIDIA CUDA compatibility and its limitations](https://docs.nvidia.com/deploy/cuda-compatibility/minor-version-compatibility.html).

## Avoid the RMS 8192-byte limit

Oracle limits [each RMS variable to 8192 bytes](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/authoring-configurations.htm). The full discovery report is an audit/local artifact, not an inline form value. The compact exporter retains the selected model revision, image/platform/source evidence, all launch/feature settings, topology, workload assumptions and CPU estimate. It removes other choices, report diagnostics and duplicate original argv evidence. UTF-8 bytes are measured, with an 8000-byte inline budget.

For local state:

```sh
terraform -chdir=terraform/stacks/discovery output -json deployment_handoffs > work/handoffs.json
jq -jr '.["CHOICE_ID"].inline_json' work/handoffs.json > work/choice.json
```

Paste the contents of `work/choice.json`, not the full handoffs map. If using an RMS state download, extract `.outputs.deployment_handoffs.value` first. A successful RMS JSON Plan instead contains `.planned_values.outputs.deployment_handoffs.value`.

If `inline_json` is null, export that entry's `object_json` with `jq -jr` (no added newline), upload those exact bytes to a private Object Storage object, and enable optional settings in the deployment form. Leave inline JSON empty; enter:

```hcl
discovery_object_uri = "oci://us-ashburn-1/NAMESPACE/BUCKET/choice.json"
discovery_sha256     = "THE_ENTRY_SHA256"
```

Terraform reads it using the native OCI Object Storage data source and the RMS principal, in the artifact's region. The principal needs permission to read the object. No public URL/PAR or extra SDK is involved. The SHA256 is checked against the downloaded bytes. If uploading a reserialized full report instead, compute its new SHA256 and supply `selection_id` when it contains several choices. Changing whitespace changes the digest.
