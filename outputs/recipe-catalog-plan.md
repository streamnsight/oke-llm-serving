<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Recipe model list

- [x] Phase 1: enumerate commit-pinned YAML recipes from vLLM, vLLM recipes and vLLM-Omni; include every task and named checkpoint variant.
- [x] Phase 2: merge duplicate model IDs, preserve recipe dates/provenance, sort alphabetically, and provide optional explicit recipe-age filtering with undated entries retained.
- [x] Phase 3: regenerate RMS choices; resolve model revisions during discovery rather than manufacturing frozen HF revisions from recipe commits.
- [x] Phase 4: test sorting, variants, duplicates, dates, filters and generated schema; refresh live sources and verify packaging.

Recipe dates are not model release dates. Listing a recipe is not a serving validation claim. Live recipe resolution and broader engine/estimator support remain separate work.

Verification: live refresh enumerated 195 core, 215 recipe-repository and 31 Omni recipes at pinned commits, producing 517 unique models/variants. Nine Node command/catalog/schema/manifest tests and three discovery Terraform tests passed. The packaging-time refresh completed, and the ZIP passed uniqueness/order/private-file exclusion checks. Extracted Terraform initialization and validation succeeded; real RMS form execution remains untested.
