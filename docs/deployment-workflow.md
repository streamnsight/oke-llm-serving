<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

# Model discovery to OKE deployment

The source now contains both Terraform stacks. Model profiling uses HCL/HTTP; dynamic regional discovery uses a packaged Go SDK executable behind the external data source. Packaging and DevOps use Bash/curl/jq. No stack invokes another Terraform process. Infrastructure application does not automatically run a deployment pipeline.

## Discover and choose

Run `terraform/stacks/discovery` locally or set that working directory in OCI Resource Manager. Enter a public Hugging Face URL/ID. Supply context, concurrency, compute/KV dtype and a new observation ID. The catalog pins upstream recipe provenance; model revisions are resolved and pinned during discovery for both listed and custom models.

```sh
terraform -chdir=terraform/stacks/discovery output -json discovery > work/discovery.json
jq '.assessment | {status, candidates}' work/discovery.json
```

The planner checks a release-specific engine catalog, conventional attention architecture, explicit model-card version hints, GPU compute capability, per-rank VRAM, TP head divisibility/KV replication, PP stages and reported AD instance capacity. Runtime overhead applies per GPU. Weight and KV estimates are conservative assumptions rather than measured performance. TP stays within a host; PP spans hosts; replicas require separate hosts. Multiple candidates share the same physical supply and cannot be added together.

A candidate is eligible for an allocation attempt, not certified at runtime. Quota/headroom and hardware capacity are separate evidence. Unknown metadata or unsupported requirements need review; the assessment includes a validation prompt. A regex match from a model card does not authorize executing its instructions. Missing matches do not prove compatibility.

## Export a selected deployment

Copy `terraform/stacks/deployment/target.example.json` to an ignored local file and fill in the existing cluster, regional image/subnet OCIDs and target compartment. All target resources must be in the selected region. The GPU image must be an OKE-compatible image with the correct NVIDIA drivers/toolkit; the CPU image must match its shape.

```sh
bash scripts/select-deployment.sh work/discovery.json CANDIDATE_ID work/target.json > work/deployment.tfvars.json
terraform -chdir=terraform/stacks/deployment init
terraform -chdir=terraform/stacks/deployment plan -var-file="$PWD/work/deployment.tfvars.json" -out="$PWD/work/deployment.tfplan"
terraform -chdir=terraform/stacks/deployment apply "$PWD/work/deployment.tfplan"
```

For RMS, create a second stack with working directory `terraform/stacks/deployment` and use the exported variables. The deployment form describes the handoff fields; discovery cannot dynamically change the form of another stack. Re-run discovery when requirements change. Change `observation_id` before a new allocation attempt to refresh the deployment module’s native capacity report; discovery itself now reads fresh SDK reports during Plan.

Allocation rechecks target-compartment entitlement in GPU units, selected quantity, image/shape compatibility, active cluster and hardware capacity. It creates a retained GPU pool and separate CPU pool. Supported RDMA selections also create a Compute Cluster and scoped node-pool launch policy; enhanced OKE is required. Multi-node Ethernet remains possible for other supported shapes, with performance requiring measurement. Capacity reports neither reserve hosts nor guarantee RDMA placement. A failed allocation may still require retrying later or selecting another AD/shape.

Pools use `prevent_destroy`, unique allocation ownership, and a guard against reducing the retained GPU node count. These are not capacity reservations and do not prevent hardware failure, external deletion, upgrades or cloud recovery from requiring spare capacity. Retirement requires an explicit infrastructure change. Autoscaling nodes down is intentionally absent; scale serving within retained capacity. The first recipe uses one model group per GPU host; it does not bin-pack independent models on unused GPUs.

## Bootstrap and run DevOps

The application creates a DevOps project, private versioned evidence bucket, logs, IAM policies and three pipelines. Before the first run, an existing cluster administrator must apply the emitted Kubernetes RBAC manifest:

```sh
terraform -chdir=terraform/stacks/deployment output -json bootstrap_rbac > work/bootstrap-rbac.json
kubectl apply -f work/bootstrap-rbac.json
```

IAM authorizes OCI access; it does not replace Kubernetes RBAC. The deploy principal has cluster-admin for operator/CRD installation. Validation and benchmark principals have narrower namespace/node permissions. The private DevOps subnet needs routing to the OKE API and HTTPS egress to OCI, registries, release binaries and Hugging Face. Configure the needed subnet security rules and DNS before running pipelines. The Terraform caller needs permission to create the IAM/DevOps/network-dependent resources.

Run the `deploy` pipeline from the console or OCI CLI using the IDs in the `delivery` output. It installs the pinned production-stack router, a vLLM engine for single-node groups, or LeaderWorkerSet/native multiprocessing groups for PP across nodes. The optional GPU Operator assumes the OKE GPU image already supplies drivers and toolkit. Set `install_gpu_operator = false` for a cluster already managing the NVIDIA device plugin/operator. Existing LWS/operator ownership must be checked before installing; this initial implementation does not adopt third-party Helm releases automatically.

Deploy chains a validation stage: GPU readiness/placement, requested image digests, model listing, chat requests with client-supplied history, tokenization/context inference, streaming benchmark requests at the requested concurrency, and NCCL RDMA log evidence when required. A separately runnable `validate` pipeline refreshes the success marker. No successful marker is written for a deployment awaiting validation.

## Benchmark stage and evidence

Run `benchmark` explicitly after validation. It may saturate the serving pool. The DevOps Shell stage starts a CPU-only Kubernetes Job using the official `vllm/vllm-openai-cpu` v0.32.0 image, pinned by digest. Its upstream Dockerfile installs the benchmark extras; the Job runs `vllm bench serve`. This is the official CPU distribution containing the benchmark CLI, rather than a separate image named `vllm-bench`.

The Job fetches only tokenizer/config files from the same frozen model revision. It uses the random dataset, a fixed seed, one warmup, bounded concurrency, unlimited arrival rate, and explicit input/output token counts. Configure `benchmark_requests` (default 50), `benchmark_input_tokens` (1024), and `benchmark_output_tokens` (128). Input + output + 128 template-reserve tokens must fit the selected context; the Job rejects oversized workloads. Chat templates can require more space, so actual server acceptance remains part of validation. The initial recipe disables thinking through chat-template kwargs where supported.

Native vLLM JSON and logs are archived with the deployment specification, model SHA, image digests, topology and stage status. TTFT, TPOT, inter-token/end-to-end latency percentiles and throughput remain vLLM's measurements. All requested requests must complete without reported errors. The benchmark requires a successful validation marker for the same specification before and after the run. Jobs and temporary ConfigMaps are removed after evidence capture; the Job also has a deadline and TTL. GPU telemetry sampling and workload/SLO acceptance thresholds are future additions.

This recipe validates Chat Completions. It does **not** implement durable Responses conversation IDs/history. Prefix/KV cache reuse is not conversation storage. A separate stateful API/gateway layer remains required for that product capability.

## Build, test and package

```sh
npm ci
npm test
# Optionally exercise the actual pinned chart:
HELM_CHART_FILE=/path/to/vllm-stack-0.1.14.tgz npm test
bash scripts/package-stack.sh /tmp/oke-llm-serving.zip
# Optional maintainer-only refresh before packaging:
bash scripts/package-stack.sh /tmp/oke-llm-serving.zip --refresh-catalog
```

Node and the `yaml` development dependency are used only to test generated manifests/schema; neither stack nor deployed benchmark requires Node. Installations in `node_modules` are ignored and disposable. Packaging uses committed source and excludes tests, local dependencies, Terraform caches/state and private discovery outputs. A refresh enumerates all structured recipes and named checkpoint variants from commit-pinned vLLM, vLLM recipes and vLLM-Omni sources. The list covers every task and is sorted case-insensitively by full model ID. It is recipe coverage, not runtime certification; custom IDs remain supported.

Native Terraform mocks and local rendering exercise the contracts. Actual RMS form/job execution, GPU allocation, image startup, RDMA networking and DevOps/container benchmarking still require a selected OCI target and live end-to-end validation. Do not treat mock passes as evidence those runtime steps have succeeded.

Sources: [vLLM benchmark CLI](https://docs.vllm.ai/en/latest/cli/bench/serve/), [pinned CPU image build](https://github.com/vllm-project/vllm/blob/v0.32.0/docker/Dockerfile.cpu), [production-stack](https://github.com/vllm-project/production-stack), [LeaderWorkerSet](https://lws.sigs.k8s.io/docs/).

## Recipe list maintenance

Run `npm ci`, then `make refresh-model-catalog`. Review and commit `catalogs/models.json` before `make package`. The refresh uses Node only as a build-time YAML parser; RMS discovery requires only the packaged SDK executable and standard Terraform providers. A failed/truncated source fetch leaves the prior catalog in place.

`catalogs/model-policy.json` controls sources and `max_recipe_age_days`. The default `null` retains every recipe regardless of age. Setting a nonnegative number filters recipes by upstream `meta.date_added`; undated recipes remain included. `date_updated` is recorded separately. Neither date is a model release date: `release_date` remains null rather than substituting Hugging Face repository creation or recipe publication. A model remains listed if any of its recipe references survives filtering. Upstream recipe provenance is preserved per model/variant.

The reference catalog includes multimodal, embedding and vLLM-Omni entries even where the current estimator/deployment recipe cannot serve them. Listing does not authorize a deployment or imply the vLLM-Omni runtime is implemented. Live recipe/flag resolution remains separate work.
