<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

# OCI OKE LLM serving

Deploy open-weight models onto GPUs in an existing OKE cluster through a model-first workflow. The intended user experience has two Resource Manager stacks: **discover**, then **deploy a selected configuration**.

## Start here

The first stack is implemented at [terraform/stacks/discovery](terraform/stacks/discovery). Supply a public Hugging Face model URL, context length and concurrency. It returns a model profile, GPU shapes, limit/headroom observations and AD-scoped host capacity across READY subscribed regions.

```sh
terraform -chdir=terraform/stacks/discovery init
terraform -chdir=terraform/stacks/discovery plan -var-file=/path/to/request.tfvars.json -out=/path/to/discovery.tfplan
terraform -chdir=terraform/stacks/discovery apply /path/to/discovery.tfplan
terraform -chdir=terraform/stacks/discovery output -json discovery
```

For RMS packages, run `make package` from the repository root. This writes separate discovery and deployment ZIPs to `work/packages/`; select the corresponding `terraform/stacks/...` working directory when uploading. Packages use committed HEAD. See [RMS packaging and JSON export](docs/rms-discovery.md).

For RMS, use this repository as the configuration source and set the working directory to `terraform/stacks/discovery`. Its `schema.yaml` describes the user inputs. See [RMS setup, scope and limitations](docs/rms-discovery.md).

Hugging Face profiling uses `hashicorp/http` and HCL. OCI regional discovery uses Bash, OCI CLI and jq through `hashicorp/external`, dynamically scanning subscribed regions without provider aliases. These tools must be installed on the execution host (OCI CLI was verified on the tested RMS host). There is no Go build, custom Python script or nested Terraform invocation. Deployment admission/allocation remains native `oracle/oci`.

Discovery creates reports, not GPU allocations. Counts represent available instances at the observation time and do not reserve them. Hub-published model counts are declared metadata, not independent tensor inspection. Discovery now includes conservative per-rank GPU layouts and engine compatibility assessment. Execution evidence and remaining cloud validation are recorded in [project status](outputs/project-status.md).

## Deploy a selected configuration

The deployment stack at `terraform/stacks/deployment` creates retained GPU/CPU pools, optional supported RDMA Compute Cluster placement, and OCI DevOps deploy, validation and benchmark pipelines. Select a discovery candidate and export its immutable model/image/topology settings using `scripts/select-deployment.sh`.

See the [complete deployment workflow](docs/deployment-workflow.md) for the target-file example, RMS handoff, Kubernetes RBAC bootstrap, official vLLM CPU benchmark container and validation boundaries. Cloud/GPU/DevOps execution remains pending a selected target. Durable Responses conversation storage remains a separate API-layer feature.

## Documentation

[Runtime recipe/image resolution and expert deployment](docs/runtime-serving-resolution.md) explains dynamic stable/nightly lookup, frozen arguments and GPU alternatives. [Flint assessment](docs/flint-assessment.md) records the upstream evidence and remaining estimation/runtime limits.

- [Model profile inputs, arithmetic and evidence](docs/model-profile.md)
- [Native OCI inventory and capacity modules](docs/oci-discovery.md)
- [Current status and implementation checklist](outputs/project-status.md)
- [Live validation record](outputs/oci-discovery-validation.md)
- [Architecture and deployment plan](outputs/oci-oke-model-deployment-plan.md)
- [Kubernetes LLM serving ecosystem research](outputs/kubernetes-llm-serving-report.md)

User-specific reports/state stay in ignored local artifacts; reusable modules, examples and provider locks are checked in.
