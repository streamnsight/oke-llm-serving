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

For RMS, use this repository as the configuration source and set the working directory to `terraform/stacks/discovery`. Its `schema.yaml` describes the user inputs. See [RMS setup, scope and limitations](docs/rms-discovery.md).

Everything in the discovery path uses Terraform providers and HCL. Hugging Face JSON comes through `hashicorp/http`; OCI observations use `oracle/oci`. There are no Python/Bash analyzers, external-program wrappers or nested Terraform invocations. The model-only example remains at `terraform/examples/model-profile`.

Discovery creates reports, not GPU allocations. Counts represent available instances at the observation time and do not reserve them. Hub-published model counts are declared metadata, not independent tensor inspection. Per-GPU VRAM/topology assessment and model-to-shape layout recommendations remain subsequent work. Actual RMS execution still needs validation; local provider execution is tested.

## Deployment stack (next phase)

The user selects region, AD, OKE cluster, shape and node quantity, with the model pinned to its resolved revision. The deployment stack will allocate retained GPU infrastructure and OCI DevOps resources. DevOps will install cluster components, serving frameworks and API components, then validate inference. This phase is not implemented yet.

## Documentation

- [Model profile inputs, arithmetic and evidence](docs/model-profile.md)
- [Native OCI inventory and capacity modules](docs/oci-discovery.md)
- [Current status and implementation checklist](outputs/project-status.md)
- [Live validation record](outputs/oci-discovery-validation.md)
- [Architecture and deployment plan](outputs/oci-oke-model-deployment-plan.md)
- [Kubernetes LLM serving ecosystem research](outputs/kubernetes-llm-serving-report.md)

User-specific reports/state stay in ignored local artifacts; reusable modules, examples and provider locks are checked in.
