<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

# Model discovery to OKE deployment

Discovery now resolves runtime recipes/images and supports a frozen expert handoff; see [the current workflow](runtime-serving-resolution.md). There is no static model/engine catalog or migration interface.


The source now contains both Terraform stacks. Model profiling uses HCL/HTTP; dynamic regional discovery uses Bash/OCI CLI/jq behind the external data source. Packaging and DevOps use Bash/curl/jq. No stack invokes another Terraform process. Infrastructure application does not automatically run a deployment pipeline.

## Discover and choose

Run `.` locally, or upload the discovery ZIP to OCI Resource Manager with working directory `.`. Enter a public Hugging Face URL/ID. Supply context and concurrency. Image selection and serving overrides are deployment concerns; discovery uses stated automatic memory assumptions. Recipe source identity is obtained live and model revisions are pinned during discovery.

```sh
terraform output -json deployment_inputs > work/deployment-inputs.tfvars.json
jq '.discovery.assessment | {status, recommended_selection_id, suggestions}' work/deployment-inputs.tfvars.json
```

The planner checks dynamically assessed engine evidence, conventional attention architecture, explicit model-card version hints, GPU compute capability, per-rank VRAM, TP head divisibility/KV replication, PP stages and reported AD instance capacity. Runtime overhead applies per GPU. Weight and KV estimates are conservative assumptions rather than measured performance. TP stays within a host; PP spans hosts; replicas require separate hosts. Multiple candidates share the same physical supply and cannot be added together.

A candidate is eligible for an allocation attempt, not certified at runtime. Quota/headroom and hardware capacity are separate evidence. Unknown metadata or unsupported requirements need review; the assessment includes a validation prompt. A regex match from a model card does not authorize executing its instructions. Missing matches do not prove compatibility.

## Pass the assessment into deployment

Copy `templates/deployment/target.example.json` to an ignored local file and select the existing cluster and assessment ID. The stack resolves regional OKE images, known worker/pod subnets and NSGs, CPU sizing and boot storage. Its default preview creates no OCI resources. All target resources must be in the selected region. See [preview defaults and the RMS size-safe handoff](deployment-preview.md).

```sh
terraform -chdir=templates/deployment init
terraform -chdir=templates/deployment plan -var-file="$PWD/work/deployment-inputs.tfvars.json" -var-file="$PWD/work/target.json" -out="$PWD/work/deployment.tfplan"
terraform -chdir=templates/deployment apply "$PWD/work/deployment.tfplan"
```

Add `selection_id` to target.json (candidate or sizing-option ID). Model identity, workload assumptions, assessed image and known topology are loaded from the JSON automatically. For an undetermined option, supply expert topology and per-rank memory in deployment. For RMS, upload the deployment ZIP to a second stack in the selected region with working directory `.`, paste the chosen `deployment_handoffs[ID].inline_json` into **Discovery JSON**, and use the dynamic cluster picker. The compartment defaults to the stack compartment. If the payload is too large, use native authenticated Object Storage input. Do not paste the full report into an RMS variable. The deployment form describes the handoff fields; discovery cannot dynamically change the form of another stack. Re-run discovery when requirements change. Change `observation_id` before a new allocation attempt to refresh the deployment module’s native capacity report; discovery itself now reads fresh CLI reports during Plan.

After reviewing `deployment_preview`, explicitly set `provision_resources = true` and run a new Plan before applying allocation. Do not disable provisioning again on an allocated state. Allocation rechecks target-compartment entitlement in GPU units, selected quantity, image/shape compatibility, active cluster and hardware capacity. It creates a retained GPU pool and separate CPU pool. Supported RDMA selections also create a Compute Cluster and scoped node-pool launch policy; enhanced OKE is required. Multi-node Ethernet remains possible for other supported shapes, with performance requiring measurement. Capacity reports neither reserve hosts nor guarantee RDMA placement. A failed allocation may still require retrying later or selecting another AD/shape.

Pools use `prevent_destroy`, unique allocation ownership, and a guard against reducing the retained GPU node count. These are not capacity reservations and do not prevent hardware failure, external deletion, upgrades or cloud recovery from requiring spare capacity. Retirement requires an explicit infrastructure change. Autoscaling nodes down is intentionally absent; scale serving within retained capacity. The first recipe uses one model group per GPU host; it does not bin-pack independent models on unused GPUs.

## Bootstrap and run DevOps

The application creates a DevOps project, private versioned evidence bucket, logs, IAM policies and three pipelines. Before the first run, an existing cluster administrator must apply the emitted Kubernetes RBAC manifest:

```sh
terraform -chdir=templates/deployment output -json bootstrap_rbac > work/bootstrap-rbac.json
kubectl apply -f work/bootstrap-rbac.json
```

IAM authorizes OCI access; it does not replace Kubernetes RBAC. The deploy principal has cluster-admin for operator/CRD installation. Validation and benchmark principals have narrower namespace/node permissions. The private DevOps subnet needs routing to the OKE API and HTTPS egress to OCI, registries, release binaries and Hugging Face. Configure the needed subnet security rules and DNS before running pipelines. The Terraform caller needs permission to create the IAM/DevOps/network-dependent resources.

Run the `deploy` pipeline from the console or OCI CLI using the IDs in the `delivery` output. It installs the production-stack router, a vLLM engine for single-node groups, or LeaderWorkerSet/native multiprocessing groups for PP across nodes. GPU/network support is reused from the existing OKE-managed add-ons and node image. Terraform records enhanced-cluster add-on versions; the pipeline waits for Ready allocation nodes advertising the requested GPU/RDMA resources. It does not install a GPU Operator or RDMA plugin, or enable/upgrade cluster add-ons. See [OKE-managed GPU/network prerequisites](oke-managed-addons.md) for RDMA resource detection and existing Multus network attachments. Existing LWS ownership must be checked before installing; this initial implementation does not adopt third-party Helm releases automatically.

Deploy chains a validation stage: GPU readiness/placement, requested image digests, model listing, chat requests with client-supplied history, tokenization/context inference, streaming benchmark requests at the requested concurrency, and NCCL RDMA log evidence when required. A separately runnable `validate` pipeline refreshes the success marker. No successful marker is written for a deployment awaiting validation.

## Benchmark stage and evidence

Run `benchmark` explicitly after validation. It may saturate the serving pool. The DevOps Shell stage starts a CPU-only Kubernetes Job using the official `vllm/vllm-openai-cpu` v0.32.0 image, pinned by digest. Its upstream Dockerfile installs the benchmark extras; the Job runs `vllm bench serve`. This is the official CPU distribution containing the benchmark CLI, rather than a separate image named `vllm-bench`.

The Job fetches only tokenizer/config files from the same frozen model revision. It uses the random dataset, a fixed seed, one warmup, bounded concurrency, unlimited arrival rate, and explicit input/output token counts. The normal RMS form hides benchmark tuning. Defaults are 50 requests, up to 1024 input tokens and up to 128 output tokens, reduced for shorter contexts; explicit Terraform overrides remain available. The benchmark pipeline exposes `BENCHMARK_REQUESTS`, `BENCHMARK_INPUT_TOKENS` and `BENCHMARK_OUTPUT_TOKENS` as per-run overrides, parsed as numeric data rather than shell substitutions. Input + output + 128 template-reserve tokens must fit the selected context; the Job rejects oversized workloads. Chat templates can require more space, so actual server acceptance remains part of validation. The initial recipe disables thinking through chat-template kwargs where supported.

Native vLLM JSON and logs are archived with the deployment specification, model SHA, image digests, topology and stage status. TTFT, TPOT, inter-token/end-to-end latency percentiles and throughput remain vLLM's measurements. All requested requests must complete without reported errors. The benchmark requires a successful validation marker for the same specification before and after the run. Jobs and temporary ConfigMaps are removed after evidence capture; the Job also has a deadline and TTL. GPU telemetry sampling and workload/SLO acceptance thresholds are future additions.

This recipe validates Chat Completions. It does **not** implement durable Responses conversation IDs/history. Prefix/KV cache reuse is not conversation storage. A separate stateful API/gateway layer remains required for that product capability.

## Build, test and package

```sh
npm ci
npm test
# Optionally exercise the actual pinned chart:
HELM_CHART_FILE=/path/to/vllm-stack-0.1.14.tgz npm test
make check-packages
# Or package a single stack:
PACKAGE_STACK=discovery bash scripts/package-stack.sh /tmp/oke-llm-discovery.zip
```

Node and the `yaml` development dependency are used only to test generated manifests/schema; neither stack nor deployed benchmark requires Node. Installations in `node_modules` are ignored and disposable. Packaging uses committed source and excludes tests, local dependencies, Terraform caches/state and private discovery outputs.

Native Terraform mocks and local rendering exercise the contracts. Actual RMS form/job execution, GPU allocation, image startup, RDMA networking and DevOps/container benchmarking still require a selected OCI target and live end-to-end validation. Do not treat mock passes as evidence those runtime steps have succeeded.

Sources: [vLLM benchmark CLI](https://docs.vllm.ai/en/latest/cli/bench/serve/), [pinned CPU image build](https://github.com/vllm-project/vllm/blob/v0.32.0/docker/Dockerfile.cpu), [production-stack](https://github.com/vllm-project/production-stack), [LeaderWorkerSet](https://lws.sigs.k8s.io/docs/).
