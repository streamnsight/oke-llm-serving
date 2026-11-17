<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Independent model stack identities

Notification topics require tenancy-unique names. A model/cluster hash is shared by separate stacks and can conflict while an older stack is destroying. Retained namespaces also remain bound to their old project.

Use a Terraform-state-persisted UUID with a 12-hex suffix for new notification topics, deriving the project name from its owned topic. No timestamps, scans, shared-topic adoption or random provider dependency. Preserve existing topic names with ignore_changes; derive the existing project name from that observed name. Legacy topic names expose a null instance key so the old default namespace remains unchanged. New instances hash their instance key into the default namespace; explicit namespace overrides are preserved. No GPU allocation or recycling is part of this fix.

1. [x] Add focused uniqueness, punctuation, rerun and legacy compatibility regressions; implement project/topic identities and independent default namespaces.
2. [ ] Validate the module and actual model ZIP, review the failed stack's fixed-source Plan, and verify that existing GPU resources remain untouched. Do not silently trigger model deployment to test metadata.
3. [ ] Commit, validate release archives, refresh discovery publications with preserved inputs, record live results, merge to main and rebuild. Provide the corrected model bundle for retry.

The identical-input regression failed against the old module (both projects named same-model), then all five default Terraform 1.9.8 module tests passed. An isolated legacy-state upgrade regression passed both runs with Terraform 1.14; it verifies no topic/project rename and a null legacy namespace key. That state-sharing regression is retained under tests/upgrades for Terraform 1.14+, outside the default 1.9.8 suite. Archive and RMS plan validation are in progress. Existing imported/custom topics are not automatically adopted; each stack owns its own metadata. Topic/project names are retained for their resource lifetime. Explicitly reusing another project's retained namespace is still rejected by trusted onboarding.
