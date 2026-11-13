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

## Console tag and empty NSG controls

The next reported error was the Console-generated `ZipOrigin` tag: its value was 288 characters, above OCI's 256-character limit. Repository Terraform declares no such tag. Both key and value were cleared in the user's pending Stack information form; Review then contained no Tags section. Create was not clicked. The GPU pool's separate allocation-ownership tag is retained.

Review also exposed empty NSG controls serialized as `[""]`. Removing the last row immediately recreated another blank row. The infrastructure template now filters blank, whitespace and null entries, preserving inherited NSGs when nothing remains; explicit IDs are trimmed and deduplicated. Native tests cover both blank and mixed inputs. This source correction requires a new ZIP: the existing wizard still references its original immutable object.

Ten infrastructure tests passed. A prefilled Frankfurt replacement was rendered locally from the same model/selection using the real archive provider with OCI mocked. Its ZIP CRC, extracted Terraform validation and three preview/expert-edit/region tests passed, including the blank NSG inputs. The artifact is work/packages/oke-llm-infrastructure-frankfurt-fixed.zip; no new capacity assessment is implied. A tag-free Review screenshot is work/validation/frankfurt-rms-tag-free-review.jpg. The agent did not click Create.

## Repeated origin tag: publication fix

The user's next quick-create wizard recreated `ZipOrigin` and displayed **Invalid tags**. Its URL was 285 characters, including a 64-character PAR token and the descriptive archive path. The prior manual cleanup did not solve future launches. The new pending wizard's key/value were cleared and Review again had no Tags heading; no submission was made. Its other settings were preserved. Evidence is work/validation/frankfurt-rms-tag-cleared-current.jpg.

The publisher now uploads the same generated archive to a fixed-length `rms/<run-id>-<option-hash>.zip` launch object alongside its descriptive archive. The existing object-read PAR is scoped to the launch copy. A precondition rejects final package URLs above 256 characters. The Console-added tag is not suppressed by Terraform; the generated URL now fits its value limit. Local publisher tests use a realistic 64-character token, long model paths, matching archive sources/checksums and an overlength URL rejection. New cloud objects/PARs have not been published by the agent; testing of a newly published short link in the live Console remains pending.
