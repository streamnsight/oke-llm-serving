<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Repository layout and ownership

The repository root is discovery and the single released entry ZIP. Downstream Terraform roots live in `templates/`; generated RMS packages put their main.tf at the ZIP root. Runtime scripts, charts and data stay inside the module that owns them. Root `scripts/` and `tests/` are development/build tools.

| Module group | Responsibility |
| --- | --- |
| `modules/discovery` | Hugging Face profile, recipe/image resolution, regional inventory/capacity, deployment choices and bundle publication |
| `modules/infrastructure` | Existing OKE target/image lookup and retained GPU allocation |
| `modules/cluster-add-ons` | Cluster-owned DevOps project, shared controllers, monitoring and optional autoscaling |
| `modules/llm-deployment` | Model-owned releases/pipelines and optional weight staging |
| `modules/shared` | Native Helm delivery, Generic Artifact inputs/results, release ownership, locking and explicit teardown |

The GPU specification catalog belongs to `modules/discovery/accelerator-inventory/data/gpus.json`; allocation also reads it. Controller chart defaults belong to `modules/cluster-add-ons/platform-bootstrap/data/components.json`. Recipe-derived serving images and argv are separate from controller dependencies. No static model/engine catalog is needed.

Infrastructure owns pools, Compute Clusters, shared controllers and their delivery project/repositories. Each model owns an independent project, private OKE environment, artifact repositories, release, routes/cache/scaling instances and pipelines; cluster/pool metadata is resolved at launch/runtime. Model teardown must not delete retained infrastructure, shared APIs or data. Object Storage is for stack ZIPs and optional model data; software artifacts and execution evidence use Artifact Registry/OCIR.

Terraform module labels/resource names stay stable during directory reorganization. Run `terraform init` after updating source paths to refresh the local module cache; directory moves do not require a second state or reallocation of existing GPU hosts. Packaging retains the same grouped module paths and validates relocated references.

`work/` contains ignored local state/report backups, private runtime evidence and built ZIPs. Node/YAML is a development-test dependency only; it is not packaged or required by RMS runtime discovery.
