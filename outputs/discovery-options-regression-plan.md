<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Discovery options and capacity labels regression

1. [x] Inspect actual latest Qwen 27B report and saved RMS state. BF16 compatibility passes for A10/A100. The live workload is 262144 tokens x 4, rather than the previous 4096 x 4. The generic budget stacks workspace and margin and can also remove the previously working short-context four-A10 configuration. B4 A100 shapes are missing from the catalog. Keep the requested workload unchanged unless the user selects another.
2. [x] Reproduce the short-context regression using actual metadata, then correct overlapping planning allowances without model-name special cases. Keep FP8/unknown kernel exclusions and strict physical capacity/headroom checks. Expose actionable per-shape fit diagnostics rather than an unrelated global no-capacity explanation.
3. [x] Render regional configured limit/headroom as `limit 32 / left 32`, with scope/unit on a separate line and only quantities bold. Preserve zero and unknown values.
4. [x] Add the missing live A100 shape from primary evidence, test dtype/fit exclusions and both context sizes, validate the rendered report in a browser and actual ZIPs in Terraform 1.5.7. Commit and merge after validation, rebuild packages, update only the discovery source and inspect a live Plan before refreshing its report. Never allocate/recycle GPUs or execute model pipelines.

## Validation record

Actual metadata replay first failed with zero short-context options, then passed after correcting overlapping workspace/margin allowances. A 4096x4 profile again yields a four-A10 TP4 suggestion at 71.83 GB payload; the unchanged 262144x4 profile needs 396.53 GB and correctly has no single-host A10 choice. The latter is a workload/layout exclusion, not BF16 incompatibility. The report now includes that reason and does not promote a zero-capacity observation in another AD into a global no-capacity claim.

Root Terraform: 14 passed including both full profile/planner/report replay cases. Focused modules: profile 30, planner 57, report 16, inventory 11 passed. Report JavaScript: 17 passed. CLI discovery: 15 passed with Node 20's experimental default ESM flag for its existing extensionless mock executable. FP8 exclusions and P100 BF16 exclusions remain covered. Native and CLI B4 inventory both report 40 GB per GPU using the Oracle source below. B4 Compute Cluster placement remains unverified/disabled.

Saved live state and raw logs stay outside source/packages. Metadata replay and report checks do not establish runtime model fit.

Sources: https://raw.githubusercontent.com/oracle-samples/oci-data-science-ai-samples/main/ai-quick-actions/supported-gpu-shapes.md ; https://developer.nvidia.com/cuda/gpus .

Browser replay verified the restored option, `limit 64 / left 64` label, no reported failures for the fitting workload, and no horizontal overflow on desktop or at 390px.


The discovery entry ZIP and both embedded downstream roots passed native Terraform 1.5.7 initialization/validation. Fix commit `4ca1575` was merged into main and rebuilt, then uploaded to the existing discovery stack with an ETag guard and all current stack variables preserved. At upload time `context_length` was absent, so the existing Terraform 4096 default applied; concurrency remained 4. Reviewed live Plan `ocid1.ormjob.oc1.us-chicago-1.amaaaaaafigrwqyaydb67at62ilfvcaeruam7rna73x32wvmd6kyrfxnpcya` contained only archive/report/ZIP/PAR/publication metadata changes. Apply `ocid1.ormjob.oc1.us-chicago-1.amaaaaaafigrwqyaqdsvqgoyvsndrgc2qgisbebw7lsfhf2o6smbpcoxcfda` succeeded.

The actual published report confirms five choices: A10.4 in Montreal and Melbourne, B4.8 in Frankfurt and Osaka, and GPU4.8 in Mumbai. Its Qwen 27B payload budget is 71.83 GB at 4096x4. PHX AD-3 A10.1 carries current limit 32 / left 32. The original 262144x4 workload remains a separate larger sizing case, not silently assumed to fit. No GPU, node-pool or DevOps execution mutation occurred. Signed links and raw state/logs are kept out of committed source.
