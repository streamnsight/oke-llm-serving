<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Review each stage with Terraform Plan

Use the configured ZIPs published by the preceding stack. The former combined preview/inline JSON handoff has been removed.

Infrastructure Plan resolves the selected cluster/image/network and shows retained GPU allocation and shared component resources. The temporary `skip_gpu_allocation=true` development switch skips GPU allocation only; it still creates DevOps metadata and CPU component pipelines. Do not use it to remove an existing allocation. Known missing OKE GPU/network prerequisites block the normal allocation path; image metadata is not proof of functioning CUDA/RDMA.

Model Plan contains model-owned pipelines, artifacts, chart repository and scoped authorization. It must contain no GPU pools, Compute Clusters/instances, project creation, shared controllers or model-data bucket ownership. Model Apply creates those delivery resources and starts no deployment automatically. A CPU-debug infrastructure binding can create model pipelines, but execution rejects an absent real GPU allocation.

Editable HCL/schema defaults live in the generated ZIP. Full model and platform specifications are input files, so the RMS 8192-byte variable limit does not require truncated discovery JSON or tfvars overrides.

See [the workflow](deployment-workflow.md) and [bound model stack](model-binding.md).
