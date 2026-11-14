<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Generated infrastructure and model bundles

Discovery publishes one configured infrastructure ZIP for every capacity-confirmed option. After infrastructure identifies its actual cluster, project, OKE environment, repositories and allocation, it publishes a configured model-only ZIP into the same discovery bundle bucket, using a publication-region provider alias when necessary.

Every runnable ZIP has main.tf/schema.yaml at its root. It includes only its required module closure. Infrastructure also embeds the next model template; a final model ZIP embeds no discovery/infrastructure publisher or parent template. The archive resource builds at Apply, including a saved Plan transferred to another worker.

Generated defaults are present in both `recommendations_override.tf.json` (Terraform variable declaration defaults) and `schema.yaml`. User edits remain effective. There is no tfvars file shadowing RMS values. Full frozen specifications are files under `inputs/`; model ZIPs contain `model-spec.json` and `platform-binding.json`, avoiding large RMS JSON variables.

Descriptive object folders remain `models/<model>/<region>/<shape>/`; timestamps/run IDs are only in filenames. A second short-path copy supports bounded RMS `ZipOrigin` URLs. Scoped read PARs expire; rebuilding a local ZIP does not update existing objects/links. RMS launch URLs select the deployment region even when artifact storage is elsewhere.

See [infrastructure publication](infrastructure-publication.md), [model binding](model-binding.md) and [RMS discovery](rms-discovery.md) for operational details. Bundles contain no credentials and never start model execution merely by being opened or applied.
