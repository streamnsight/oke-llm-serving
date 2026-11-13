<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# RMS launch-link investigation — 2026-11-12

The user reported a Frankfurt quick-create GetPackage InvalidParameter(400). Its object resides in Chicago, which is independent of the target infrastructure region. The primary discovery button selected the recommended São Paulo choice; the remaining choices were present in deployment_options.

Read-only checks against the user's existing PAR returned HTTP 200, Content-Type application/zip and 34,519 bytes from both the native namespaced customer endpoint and the classic Object Storage endpoint. Both downloads have SHA256 `11a4dfd6d7af5cb9c281553c1c779a4aa2dfc40a246168a59d82cf3c4a96bc62`. ZIP CRC verification passed; root Terraform/schema assets are present. No PAR token or download URL is stored in this report.

The storage object and PAR therefore work. The new customer hostname is a likely RMS importer compatibility issue: the documented quick-create provider URL uses the classic endpoint. The correction preserves the existing PAR path and storage region, changing only that commercial hostname; launch region stays Frankfurt. Existing classic and other-realm hostnames are untouched. The user has a corrected link for comparison without republishing artifacts.

The existing error was observed in the authenticated Console. After navigation, the Console did not render its Resource Manager view during the browser check, so successful import through variable configuration has not yet been established. Confirmation from the user is pending. No stack was created, and no GPU, bucket, object or PAR was modified.

Local regression tests cover a namespaced Chicago endpoint launching a Phoenix stack, preservation of encoded PAR path characters, unchanged classic/other-realm endpoints and output choice counts. The primary button is now explicitly labelled as the recommendation, and the Console schema displays the available-option count beside the all-options JSON.
