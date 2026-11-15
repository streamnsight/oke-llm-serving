<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Blank RMS scopes and partial regional capacity

The failed Chicago discovery Apply accepted shape_names=[""] and scanned the full inventory. Its actual error was recommendations.tf: regional_known_hosts passed null to sum(). one([]) returns null without raising an error, so try(one(...), 0) did not supply zero for ADs without positive observations. Zero here is only the contribution to a known-host lower bound; missing/unknown capacity must remain unknown in raw evidence and complete regional totals.

1. [x] Reproduce the ranking error with one available AD, a zero-capacity AD and an unreported AD. Normalize whitespace/blank/null RMS rows at the Terraform request boundary; keep explicit scopes trimmed/deduplicated and genuine invalid region validation intact.
2. [x] Replace null contributions to the known-supply sum safely; verify mixed ADs, blank scopes and existing availability/ranking regressions with mocked/local tests. Do not run another live capacity scan or mutate cloud resources.
3. [x] Validate the committed-source package with Terraform 1.5.7 and integrate the tested fix into local main. Preserve the user's unstaged README.md and schema.yaml edits, staged AGENTS.md, separate untracked review and original state/tfvars. Those user edits are excluded from commits and packaging.

Validation so far:

- The new mixed-AD regression reproduced the failed RMS job's sum() error before the fix.
- Deployment planner: 53 passed; discovery/publication root: 13 passed; CLI lookup: 14 passed.
- An offline planner replay of the failed job's saved inventory (16 regions, 60 shape/AD entries) passed using saved model and HTTP recipe data. It made no new capacity requests and does not claim current capacity.
- The rebuilt discovery ZIP and both embedded deployment template roots pass native Terraform 1.5.7 initialization and validation. The ZIP contains the null-sum fix and Terraform scope normalization; development tests, state and local input files are excluded.
- No GPU or other cloud resources were changed. Local replay evidence remains under ignored work/.
- No Node dependencies were installed. Isolated test/package workspaces were removed automatically. RMS must be updated to the rebuilt source ZIP before rerunning; an existing stack source retains its old code.
