<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# RMS launch-link investigation — 2026-11-12

The user reported a Frankfurt quick-create GetPackage InvalidParameter(400). Its object resides in Chicago, which is independent of the target infrastructure region. The primary discovery button selected the recommended São Paulo choice; the remaining choices were present in deployment_options.

Read-only checks against the user's existing PAR returned HTTP 200, Content-Type application/zip and 34,519 bytes from both the native namespaced customer endpoint and the classic Object Storage endpoint. Both downloads have SHA256 `11a4dfd6d7af5cb9c281553c1c779a4aa2dfc40a246168a59d82cf3c4a96bc62`. ZIP CRC verification passed; root Terraform/schema assets are present. No PAR token or download URL is stored in this report.

The storage object and PAR work. Changing the newer customer hostname to the classic Object Storage hostname resolves this RMS import compatibility issue for the reported link. The correction preserves the existing PAR path and storage region; launch region stays Frankfurt. Existing classic and other-realm hostnames are untouched. No re-upload or new PAR was required.

The user confirmed the corrected link opens the wizard. The authenticated Console was then inspected at Configure variables: Frankfurt AD-2, BM.GPU.A10.4, one host and a 204 GiB disk recommendation were populated. The user had already selected a cluster; their settings were preserved. No stack was created by the agent, and no GPU, bucket, object or PAR was modified. A local screenshot is retained in work/validation/frankfurt-rms-import.jpg.

Local regression tests cover a namespaced Chicago endpoint launching a Phoenix stack, preservation of encoded PAR path characters, unchanged classic/other-realm endpoints and output choice counts. The primary button is now explicitly labelled as the recommendation, and the Console schema displays the available-option count beside the all-options JSON.

Publisher tests passed six runs, discovery tests eight, and Node checks 35 (two optional chart checks skipped). The actual downloaded Frankfurt ZIP passed Terraform init/validate as well as ZIP CRC verification. The rebuilt entry package and both embedded roots passed extraction/init/validate. Terraform state/tfvars bytes and the user's staged AGENTS.md were preserved.
