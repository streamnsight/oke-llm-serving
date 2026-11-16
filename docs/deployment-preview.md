<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Review deployment plans

Use the configured ZIP links in the discovery HTML report. Both infrastructure and model links are published up front; no inline JSON handoff or completed-platform binding is needed.

Infrastructure Plan shows the selected cluster/network/image, retained GPU allocation and shared component project. The temporary `skip_gpu_allocation` debug switch suppresses only GPU allocation resources; platform delivery can still be created and run on existing CPU pools. Normal use defaults to allocating the selected GPU hosts. Never flip this switch after allocation to remove managed pool resources.

Model Plan owns its independent project/environment/repositories, delivery pipelines, scoped IAM and optional model-data staging. It must contain no GPU pools, Compute Clusters/instances or shared-controller resources. Cluster is the only required infrastructure choice; pool/network defaults are inferred, with explicit advanced overrides for ambiguity. Apply requires retained infrastructure and its trusted onboarding pipeline, then runs onboarding, model deployment and independent validation. It waits for success; benchmarking and retirement remain manual.

Review image/model/parallelism/context changes as new unvalidated settings. Generated schema and HCL defaults match and stay editable; no tfvars file masks edits. Large model/recipe specifications are embedded files rather than RMS variables, avoiding the 8192-byte variable limit.

Review a saved Plan before Apply: the model stack must never mutate GPU pools or Compute resources. Its three automatic `oci_devops_deployment` resources authorize namespace onboarding, workload deployment and validation on existing capacity. Use Plan alone when reviewing definitions without running workloads. Benchmarking and guarded retirement are manual pipeline operations.
