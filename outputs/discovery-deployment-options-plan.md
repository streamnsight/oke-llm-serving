<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Keep deployment policy out of discovery inputs

Discovery collects model/workload and capacity scope, then publishes recommendations. Users choose optional component installation in infrastructure and model release policy in the model stack.

1. [x] Remove monitoring, autoscaling and distribution from root variables/schema and publication input wiring. Keep planner recommendation defaults (monitoring on, scaling off); infer mandatory topology/recipe requirements as before. Weight delivery defaults belong to the model template.
2. [x] Keep downstream controls editable. Decouple model monitoring/metrics/controller requirements from the frozen discovery plan so disabling optional monitoring works, while autoscaling still requires Prometheus/KEDA. Do not install shared controllers from the model stack.
3. [ ] Verify root/schema contracts, generated ZIP defaults and downstream overrides, native Terraform 1.5.7 packaging and documentation. Commit and integrate the tested fix without changing cloud resources, GPU allocations, original state/tfvars or user-staged files.

Validation so far: 9 discovery/report form tests, the model schema contract, 11 root discovery/publication runs, 7 real-archive publisher runs and 3 extracted-model-root tests passed. The generated model tests verify monitoring can be disabled despite a frozen discovery recommendation, autoscaling still requires Prometheus/KEDA, and weight delivery can be changed to an existing PVC without creating a staging bucket. One parallel archive-provider startup failed; the isolated serial root rerun passed all 11 cases. Native packaging checks follow.
