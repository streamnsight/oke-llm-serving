<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# AD capacity row presentation

1. [x] Render one capacity row per positive AD/exact shape, with region and AD together in the first cell above shape and memory. Use only that AD's applicable limits and limit-increase evidence.
2. [x] Keep key GPU quantities bold inline with normal-weight units/host counts, and verify row identity, scope isolation, filtering, zero/unknown observations and safe rendering. Generate an offline preview from saved inventory; no additional OCI scans or cloud changes. Browser local-file preview is blocked by the existing browser policy; use renderer checks without a workaround.
3. [x] Validate/rebuild the committed discovery ZIP and merge the tested feature into local main, preserving user edits.

Validation so far:

- Renderer tests: 14 passed, including the Melbourne example's exact bold values, one row per AD, row-local limits/badges, AD filtering, zero/unknown capacity and safe text rendering.
- Terraform report tests: 15 passed. An offline HTML preview was generated from saved inventory with no new OCI scan. No cloud resources were changed.
- Published HTML remains a static snapshot; the rebuilt source ZIP must be applied by discovery to publish the updated layout. The offline preview is for presentation only and contains no deployment links.
- The committed discovery ZIP and both embedded template roots pass native Terraform 1.5.7 initialization/validation. Integrated the tested feature into local main and rebuilt the ZIP; user edits and local state are preserved.
