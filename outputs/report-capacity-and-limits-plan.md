<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Report capacity and limits without mixing scopes

Group deployment options by region, retaining each AD-specific node-pool choice and its links. Headline capacity must be the selected AD's physical supply. Present the configured limit and effective remaining headroom together, with actual REGION/AD/GLOBAL scopes and verified GPU units. Unknown values or units remain explicit; shared limits are never summed.

1. [x] Derive display-only quota records from saved inventory, expose them with each selected AD and regional shape, and update report grouping and labels. Use no additional discovery calls; leave eligibility/ranking unchanged.
2. [x] Verify mixed regional/AD/global limits, fractional/zero/unknown headroom, wrong-AD isolation, region grouping/filtering, and AD counts instead of regional totals using Terraform and renderer tests. Render saved real inventory offline. Browser local-file policy previously blocked previews; do not work around it.
3. [x] Validate the committed-source RMS package with Terraform 1.5.7, merge the tested feature into local main, rebuild, and preserve all existing user edits. No cloud scans, Apply or GPU operations.

Validation so far:

- Terraform report tests: 15 passed, covering actual REGION/AD/GLOBAL scope, selected-AD isolation, single shared regional ceilings, numeric effective quota, fractional and zero headroom, unknown limits/units, coverage and existing report output.
- Root discovery/publication tests: 12 passed. Renderer/RMS-schema tests: 12 passed, covering region grouping, per-AD headline/table counts, visible current limits/headroom, filtering, safe URLs, retained stack links and serving details.
- Offline rendering of saved inventory from 16 regions produced 13 choices grouped into 10 regions; all 13 retain applicable limits and numeric headroom without another OCI request. Browser preview is not claimed because local-file access was previously blocked; UI behavior was tested in the DOM harness.
- Eligibility and ranking code are unchanged. No cloud resources or GPU allocations were changed.
- The discovery ZIP and both embedded template roots pass native Terraform 1.5.7 initialization and validation. The tested feature is integrated into local main, and the ZIP rebuilt from committed source; user edits remain uncommitted and excluded from packaging.
