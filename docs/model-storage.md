<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Optional model weight staging

`modules/llm-deployment/model-storage` distinguishes model data from DevOps artifacts. The default `direct_huggingface` mode creates **no bucket, pipeline, artifacts or IAM**. The later model deployment downloads its pinned snapshot directly from Hugging Face into its model cache. There is no infrastructure-time model download.

The optional `object_storage` adapter creates a private, versioned Standard Object Storage bucket, retained by Terraform `prevent_destroy`, and a manually invoked DevOps Shell pipeline in the supplied project. Fixed scripts use readable inline command specs. Generic Artifact Registry holds the pinned file specification; routine status and failures go to DevOps logs. Weight shards and their completion manifest belong in the model bucket. Discovery's RMS ZIP/PAR bucket is a separate concern.

The adapter is implemented and locally tested with mocked OCI/Kubernetes interfaces. Its output deliberately remains `runtime_status = requires_validation`. No cloud staging run or staging image build has been performed. The independent model stack can create the staging resources when explicitly selected, but verified materialization into a serving volume remains pending; selecting staging does not make its weight objects consumable by the engine automatically.

## Required inputs

Enable staging only after these are known:

- An existing enhanced OKE cluster and confirmed CPU node pool, private API network access, exact Kubernetes version, and the model stack's independent DevOps project and Generic Artifact repository in the deployment region.
- A Hugging Face `owner/model`, resolved 40-character commit SHA, selected variant such as `bf16`, and explicit unique file allowlist with byte sizes. Include the selected shards, their index, tokenizer/config and modality assets the engine needs. Do not enumerate every checkpoint variant indiscriminately. Supply Hub LFS SHA256 values when published; ordinary Git files may have no SHA256 metadata.
- A tested `linux/amd64` staging image pinned by digest. It must provide Bash, curl, jq, coreutils and OCI CLI with `oke_workload_identity` authentication. No moving image default or runtime package installation is assumed.
- A CPU-pool label selector, sufficient CPU resources (Job requests 2 CPU / 4 GiB), and a retained RWO scratch PVC. The default is 64 GiB using `oci-bv`; it must fit the largest selected file plus 10% and 64 MiB. Downloads are sequential, with at most two multipart upload workers.

The namespace defaults to `<name>-staging` and is dedicated to this adapter. `namespace`, `service_account`, `cpu_node_selector`, `scratch_gib`, `storage_class`, `deadline_seconds`, `staging_image` and optional Vault secret OCID are Terraform inputs. The pipeline exposes the non-secret image and deadline as editable per-run parameters. Model identity, file allowlist, IAM identity and PVC binding remain versioned configuration artifacts; changing them requires a new Terraform specification rather than a large editable JSON Console variable.

The default Job deadline is four hours; its maximum is seven hours, with an eight-hour runner limit and cleanup/reporting headroom. OCI documents an [eight-hour maximum for command specifications and their steps](https://docs.oracle.com/en-us/iaas/Content/devops/using/command_spec.htm). Very large or slow snapshots can be staged through repeated bounded runs, reusing uploaded shards and retained partial files.

`image/Dockerfile` is a build recipe requiring a reviewed digest-pinned official OCI CLI base:

```sh
docker build --platform linux/amd64 \
  --build-arg OCI_CLI_BASE=ghcr.io/oracle/oci-cli@sha256:<reviewed-base-digest> \
  -t <your-registry>/model-stager:<version> modules/llm-deployment/model-storage/image
```

Publish the image and pass its resulting digest as `staging_image`. The Dockerfile checks that the installed CLI advertises workload identity support; a real enhanced-cluster run must still validate IAM, image access and network connectivity. Oracle publishes the [OCI CLI image source](https://github.com/oracle/docker-images/tree/main/OracleCloudInfrastructure/oci-cli); the [CLI authentication reference](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/oci.html) includes `oke_workload_identity`.

The supplied Dockerfile expects a `dnf`-based CLI base, matching Oracle's published Dockerfile. A different minimal image using only `microdnf` needs a reviewed build-time adjustment. The adapter does not try to install tools in a running Job.

## Identity and bootstrap

The DevOps runner uses **its pipeline resource principal** to authenticate to OKE and access Generic Artifact Registry. It has no model-bucket or Vault permissions. Do not copy the runner's principal environment into a Pod: it does not become that Pod's identity.

The download Job uses **OKE workload identity**, bound to the exact enhanced cluster, namespace and service account. The home-region IAM policy grants bucket inspection/read and object inspect/read/create/overwrite, with no object-delete permission. Multipart commits also require bucket read. Workload identity is not a dynamic-group identity. Oracle documents this [cluster/namespace/service-account authorization contract](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contenggrantingworkloadaccesstoresources.htm) and [Object Storage permissions](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/objectstoragepolicyreference.htm).

`bootstrap_manifest` is an explicit administrator/bootstrap contract: dedicated Namespace, ServiceAccount, retained scratch PVC, namespaced runner Role/RoleBinding and read-only node/storage-class inspection RBAC. Inspect for existing ownership before applying it; do not adopt an unrelated namespace, account or claim. It is intentionally not applied by Terraform or by the staging runner. No staging Job is created until the runner verifies account/PVC ownership, requested volume size/class, namespaced RBAC and ready CPU-only nodes. A Pending PVC is accepted only after confirming the class uses `WaitForFirstConsumer`; it is not required to be Bound before its first consumer exists. Kubernetes binds it when scheduling the Job. The runner checks Bound state when the Pod is running and again before accepting Job success. The Job checks its own bucket access before contacting Hugging Face. IAM propagation or missing network access fails staging rather than falling back to node or runner credentials.

For a gated repository, optionally set `hf_token_secret_id` and, if needed, `hf_token_secret_compartment_id`. The **Vault secret contains the token**, never a Terraform variable. The workload IAM policy restricts secret-bundle reads to that OCID. The worker reads the current version, validates an `hf_` token, writes a private temporary header file and disables shell tracing. It does not put the token in arguments, ConfigMaps, logs or artifacts. The token owner must already have accepted the model's license/access conditions. The runner does not read the secret. Vault access uses the deployment region; the secret must be available there.

## Transfer, retries and retirement

The Shell stage downloads only small scripts/configuration and a checksum-verified kubectl. It creates a ConfigMap and a bounded OKE Job targeting the explicit CPU pool, excluding GPU/allocation labels and requesting no GPUs. It never downloads weights onto the DevOps runner disk and never changes a node pool.

The worker fetches only allowlisted HTTPS files at the frozen Hugging Face revision. It never imports or executes repository code. Paths are validated and flattened into hashed scratch filenames. Partial downloads survive on the retained PVC; retries use HTTP ranges. Completed uploaded objects are skipped only after successful listing and verification of byte size, snapshot identity and stored SHA256 metadata. Where supplied, the upstream SHA256 is checked before upload. Every file gets a measured SHA256 and upload checksum verification. An unavailable upstream SHA256 is recorded as such; a computed checksum is not independent proof of source authenticity.

Objects are placed under `models/<owner--model>/<commit>/<variant>/<file-manifest-sha>/files/`. `manifest.json` is published last and verified against every selected file. It records source URLs, revision/variant, supplied and measured hashes, sizes, image and first completed run. Later runs verify and retain it. Each pipeline run logs its structured status in DevOps Logging; no mutable global readiness marker or mandatory report upload is used. A complete weight snapshot does not prove engine compatibility or inference readiness.

A fixed Job name prevents simultaneous staging runs from using the same PVC. A second execution fails without deleting the first execution's Job. Normal cleanup removes only the current run's Job and ConfigMap; it retains the account, PVC, bucket and model objects. Jobs have an active deadline and finished-job TTL. If the runner is interrupted, inspect any surviving Job before starting again; recover stale transient resources explicitly. Aborted multipart uploads can leave uncommitted parts because the workload intentionally lacks delete/abort permission; an administrator should inspect and clean those separately.

There is deliberately no purge pipeline and no automatic bucket/PVC deletion when a model is undeployed. Changing `mode` after creating the bucket will encounter its Terraform retention guard; deliberately transfer retained storage ownership before removing the adapter. Model data retirement is separate from shared platform/component teardown. Do not attach bucket deletion to Helm uninstall or GPU pool lifecycle.

## Serving from the staged copy

Object Storage is not automatically a POSIX model directory. This adapter does **not** make `vllm serve oci://...` work. The future model deployment must use a separate read-only workload identity and materialize the exact completed snapshot onto local GPU-node storage or an appropriate model PVC before the serving process starts. It must check the completion manifest, size and SHA256 of every downloaded object and point vLLM/SGLang at that local directory. The staging PVC is CPU-side transfer scratch, not an implicitly shared GPU model volume.

Plan cache capacity for the full selected snapshot, update headroom and replication across serving nodes, separately from this adapter's largest-shard scratch space. LMCache/KV cache capacity and policy are separate from weight storage. The model stack must determine cache location, distribution/replication, cold-start behavior, read-only IAM, startup/init ordering, and validation before enabling serving traffic. Those integrations remain pending.

Local checks:

```sh
terraform -chdir=modules/llm-deployment/model-storage init -backend=false
terraform -chdir=modules/llm-deployment/model-storage test
node --test modules/llm-deployment/model-storage/tests/*.test.mjs
bash -n modules/llm-deployment/model-storage/scripts/*.sh
```

The Terraform tests use mocked providers, and the Bash integration tests use fake OCI/HTTP clients. They allocate no cloud resources or GPUs. Live image pull, OKE workload identity, Vault access, storage binding, large-file network retries and model-loader integration still require environment validation.
