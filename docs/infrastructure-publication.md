<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Discovery publication

Discovery Apply publishes an HTML assessment plus separate infrastructure/model ZIPs for every confirmed option. The single `comparison_report_url` output is a typed RMS link and primary button. The HTML embeds model, memory, configuration, capacity and limit evidence plus both stacks' PAR and region-specific RMS launch URLs.

Publication storage is private and defaults to the RMS stack compartment, with an optional override. Even a zero-option run creates report storage and an expiring report PAR so the user can inspect exclusions. Disabling deployment ZIP publication keeps the report and omits both child ZIP sets. Discovery creates no GPU hosts, node pools, controllers or DevOps projects.

Each infrastructure ZIP freezes the chosen region/AD/shape/host/component requirements, editable schema/HCL defaults and template provenance in `inputs/infrastructure-spec.json`. It contains only infrastructure and shared-controller modules. The model ZIP separately freezes the model/profile/selected recipe in `inputs/model-spec.json`; it owns an independent project and resolves cluster/network/pool metadata at launch. It has no completed-infrastructure binding dependency.

Native archive resources generate the root-level ZIPs at Apply, including saved Plan/Apply jobs on separate RMS workers. Packages exclude provider caches, tests, local state and tfvars. No nested Terraform command or packaging script runs inside the stack.

Descriptive objects use `models/<owner--model>/<region>/<shape>/<kind>-<timestamp>-<run>-<selection>.zip`. Run identity is in filenames, not another directory. Each stack also has a short launch copy because RMS places its package URL in a bounded origin field. RMS URLs use the classic Object Storage endpoint and the selected deployment region, which may differ from the publication bucket's region.

The report, infrastructure and model links share the discovery publication expiry. Reapply generates a new snapshot and may replace/revoke old managed objects/PARs. Rebuilding a local source ZIP does not change existing service resources; create/update the RMS discovery source and run its new Plan/Apply to publish the changed templates.

See [report usage](rms-discovery.md), [generated bundle contents](generated-deployment-bundles.md), [infrastructure bootstrap](infrastructure-bootstrap.md) and [independent model access](model-binding.md).
