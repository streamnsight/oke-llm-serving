<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Deployment workflow

1. Package discovery with `make package`, create its RMS stack and supply model/context/concurrency. Plan and Apply create a single linked HTML report containing all confirmed choices and both sets of deployment links. No GPUs are allocated.
2. For new capacity, open an option's infrastructure link and select the existing cluster. Review the retained GPU pool/transport and required shared components. Infrastructure owns pool allocation and CPU component delivery. Reuse this state/pool for future models; do not destroy it when retiring a model.
3. After retained infrastructure and shared components are ready, open the option's model link and select the cluster. Pool/network and trusted onboarding are inferred; ambiguous choices have advanced overrides. Review Plan for this model's independent project/pipelines and three automatic executions.
4. Apply runs trusted namespace onboarding, model deployment and a separate validation pipeline in sequence, waiting for success. Runtime checks actual retained pool/controller readiness; scheduling handles contention within the retained allocation. Run the benchmark pipeline manually when desired.
5. To retire a model, run guarded model undeploy, revoke model access and only then destroy model metadata/project resources. Retained data/namespaces and shared infrastructure need separate owner-reviewed retirement.

The report distinguishes physical supply, usable quota, GPUs per replica, whole-host allocation and packed replicas. It preserves configuration provenance and unknown estimates. A capacity observation does not reserve hardware or validate a recipe on that exact image/GPU/workload.

See [discovery report](rms-discovery.md), [infrastructure bootstrap](infrastructure-bootstrap.md), [model access/lifecycle](model-binding.md) and [component responsibilities](model-layer-components.md).
