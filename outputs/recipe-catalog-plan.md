<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Recipe model list

- [x] Phase 1: enumerate commit-pinned YAML recipes from vLLM, vLLM recipes and vLLM-Omni; include every task and named checkpoint variant.
- [x] Phase 2: merge duplicate model IDs, preserve recipe dates/provenance, sort alphabetically, and provide optional explicit recipe-age filtering with undated entries retained.
- [x] Phase 3: regenerate RMS choices; resolve model revisions during discovery rather than manufacturing frozen HF revisions from recipe commits.
- [ ] Phase 4: test sorting, variants, duplicates, dates, filters and generated schema; refresh live sources and verify packaging.

Recipe dates are not model release dates. Listing a recipe is not a serving validation claim. Live recipe resolution and broader engine/estimator support remain separate work.
