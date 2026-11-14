<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Generated deployment bundles

The discovery entry ZIP contains the infrastructure and model templates plus module-owned runtime assets. Discovery Apply publishes **both** configured ZIPs for each confirmed option into its private Object Storage bucket and exposes their PAR/RMS links through one HTML report. Zero-option runs still publish the report.

Each child ZIP has `main.tf` at its root. Small recommendations populate both schema and HCL declaration defaults, leaving Console edits effective. No generated tfvars shadows user choices, and no large JSON input is pasted into RMS variables.

| Bundle | Embedded input | Owned resources |
|---|---|---|
| Infrastructure | `inputs/infrastructure-spec.json`: selected region/AD/shape/host/component requirements | Retained GPU pool/transport and shared component delivery project |
| Model | `inputs/model-spec.json`: pinned model/profile/recipe/layout | Independent per-model project/environment/repositories/pipelines, optional model staging |

The model bundle has no `platform-binding.json` and needs no infrastructure Apply outputs. Cluster selection resolves known networking/pool metadata; runtime binds readiness after infrastructure exists. Model bundles exclude infrastructure/publisher modules; infrastructure bundles exclude model modules/templates. No nested Terraform execution is used.

Descriptive ZIP objects live under `models/<owner--model>/<region>/<shape>/`; timestamps/run IDs are in filenames. Short launch copies keep RMS package URLs bounded. Report/infra/model PARs share the discovery publication time and expiry. Reapply can replace old managed objects/PARs; rebuilding the repository ZIP does not update previous links.

`make package` builds the supported entry artifact from committed HEAD. `make package-infrastructure` and `make package-model` are developer template builds. Package checks validate extracted roots and relative module references with the RMS-compatible Terraform version, excluding state, tfvars, tests, node_modules and local caches.
