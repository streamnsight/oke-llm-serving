# OCI OKE model deployment

This workspace contains the research and agreed direction for a model-first workflow that deploys open-weight LLMs onto GPU nodes in an existing OCI OKE cluster.

## Documents

- [Deployment architecture and phased implementation plan](outputs/oci-oke-model-deployment-plan.md) — user workflow, model inspection, OCI discovery, capacity checks, Terraform modules, Resource Manager stacks and DevOps delivery. The final section contains the latest refinements concerning RDMA and staged deployment.
- [Kubernetes LLM serving research](outputs/kubernetes-llm-serving-report.md) — bottom-to-top infrastructure and serving ecosystem report. Section 20 contains the production-stack repository investigation.
- [Current decisions and next steps](outputs/project-status.md) — agreed direction, implementation status and remaining decisions.

## Agreed direction

1. Inspect a Hugging Face model and estimate its requirements, with a Terraform data-only wrapper around the inspection tool.
2. Discover OCI shapes, quota/limit headroom and reported host capacity independently.
3. Compare feasible configurations, then pin the selected configuration in a deployment specification.
4. Use Terraform to allocate GPU infrastructure and create OCI DevOps resources.
5. Use DevOps to deploy cluster components and the model, then validate the result.
6. Retain scarce GPU node allocation and scale serving workloads within that allocation.

## Workspace layout

```text
README.md       Workspace entry point
outputs/        Research, plans and other user-facing deliverables
work/           Research notes and intermediate assets
```

Implementation has not started. The first work package is the Hugging Face model-inspection tool and its Terraform wrapper.
