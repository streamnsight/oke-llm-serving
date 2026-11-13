<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

# OCI OKE LLM serving

Deploy open-weight models onto GPUs in an existing OKE cluster through a model-first workflow. The intended flow separates **discovery**, **retained GPU infrastructure/shared controllers**, and **model deployment**. Current work focuses on infrastructure; model deployment/undeploy will follow.

## Start here

The first stack is implemented at [terraform/stacks/discovery](terraform/stacks/discovery). Supply a public Hugging Face model URL, context length and concurrency. It returns a model profile, GPU shapes, limit/headroom observations and AD-scoped host capacity across READY subscribed regions.

```sh
mkdir -p work
terraform -chdir=terraform/stacks/discovery init
terraform -chdir=terraform/stacks/discovery plan -var-file=/path/to/request.tfvars.json -out=/path/to/discovery.tfplan
terraform -chdir=terraform/stacks/discovery apply /path/to/discovery.tfplan
terraform -chdir=terraform/stacks/discovery output -json deployment_inputs > work/deployment-inputs.tfvars.json
```

For RMS packages, run `make package` from the repository root. This writes discovery, infrastructure and the older combined deployment ZIPs to `work/packages/`; use the ZIP root (`.`) as the working directory. Each ZIP has `main.tf`, `schema.yaml` and `modules/` at its root. Packages use committed HEAD. `make check-packages` extracts and Terraform-validates all ZIPs. The **Package RMS stacks** GitHub workflow publishes all three ZIPs as downloadable Actions artifacts on pushes/merges to `main`. See [RMS packaging and JSON export](docs/rms-discovery.md).

If linking RMS directly to the Git repository instead of uploading a packaged ZIP, set the working directory to `terraform/stacks/discovery`. Its `schema.yaml` describes the user inputs. See [RMS setup, scope and limitations](docs/rms-discovery.md).

Hugging Face profiling and recipe/variant lookup use live HTTP data and HCL; no static model/engine catalog or catalog build tool is required. OCI regional discovery uses Bash, OCI CLI and jq through `hashicorp/external`, dynamically scanning subscribed regions without provider aliases. These tools must be installed on the execution host (OCI CLI was verified on the tested RMS host). There is no Go build, custom Python script or nested Terraform invocation. Deployment admission/allocation remains native `oracle/oci`.

Discovery creates reports, not GPU allocations. Counts represent available instances at the observation time and do not reserve them. Hub-published model counts are declared metadata, not independent tensor inspection. Discovery now includes conservative per-rank GPU layouts and engine compatibility assessment. Execution evidence and remaining cloud validation are recorded in [project status](outputs/project-status.md).

## Deploy GPU infrastructure first

Use [terraform/stacks/infrastructure](terraform/stacks/infrastructure) and [the infrastructure/bootstrap instructions](docs/infrastructure-bootstrap.md). It previews and optionally provisions a GPU-only pool, reuses existing CPU pools and OKE GPU/network support, and creates a shared-controller bootstrap pipeline. No model or large discovery JSON is needed. Run `make package-infrastructure` for its RMS ZIP. Preview is the default; live allocation/bootstrap validation remains pending.

## Earlier combined deployment path

The deployment stack at `terraform/stacks/deployment` defaults to a read-only OCI preview. In RMS, paste one `deployment_handoffs[ID].inline_json` and select an existing OKE cluster; the compartment defaults to the stack's compartment. OKE images, existing subnets/NSGs, CPU sizing and storage defaults are resolved automatically. The full `deployment_inputs` report remains usable locally or through authenticated Object Storage; it exceeds RMS's 8192-byte variable limit for typical reports. See [preview and handoff instructions](docs/deployment-preview.md).

Review `deployment_preview` before enabling `provision_resources`. Provisioning creates retained GPU/CPU pools, supported RDMA Compute Cluster placement when required, and OCI DevOps deploy, validation and benchmark pipelines. No GPU resources are allocated or released by the default preview. Overrides are optional advanced controls.

Discovery now uses the vLLM Recipes JSON API to provide ranked, untested hardware-specific suggestions with frozen images and parser flags. Choose an ID from `assessment.suggestions`; `assessment.recommended_selection_id` identifies the resource-oriented default. See [recipe-derived suggestions and limitations](docs/recipe-derived-suggestions.md).

See the [complete deployment workflow](docs/deployment-workflow.md) for the target-file example, RMS handoff, Kubernetes RBAC bootstrap, official vLLM CPU benchmark container and validation boundaries. Cloud/GPU/DevOps execution remains pending a selected target. Durable Responses conversation storage remains a separate API-layer feature.

Runtime scripts and data live with their Terraform modules; root `scripts/` contains packaging tools and root `tests/` contains development checks. See [repository layout and asset ownership](docs/repository-layout.md).

## Documentation

[Runtime recipe/image resolution and expert deployment](docs/runtime-serving-resolution.md) explains dynamic stable/nightly lookup, frozen arguments and GPU alternatives. [Flint assessment](docs/flint-assessment.md) records the upstream evidence and remaining estimation/runtime limits.

- [Model profile inputs, arithmetic and evidence](docs/model-profile.md)
- [GPU-only infrastructure and shared-controller bootstrap](docs/infrastructure-bootstrap.md)
- [Native OCI inventory and capacity modules](docs/oci-discovery.md)
- [Current status and implementation checklist](outputs/project-status.md)
- [Live validation record](outputs/oci-discovery-validation.md)
- [Architecture and deployment plan](outputs/oci-oke-model-deployment-plan.md)
- [Kubernetes LLM serving ecosystem research](outputs/kubernetes-llm-serving-report.md)

User-specific reports/state stay in ignored local artifacts; reusable modules, examples and provider locks are checked in.
