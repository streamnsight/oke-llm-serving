<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Discovery layout tabs

## Phase 1 — design
- [x] Keep combined and P/D layouts in separate accessible report tabs with the same region/AD structure and shared archives.
- [x] Explain TP, PP, independent replicas, full weights per P/D role, MoE, prefix caching and routing distinctions.
- [x] Preserve legacy report rendering and explicitly mark unassessed P/D.

## Phase 2 — implementation
- [x] Render the selected backend layout; retain filters and sorting, role counts, exact AD capacity and tab-specific recommendation.
- [x] Label P/D role GPU demand separately from allocated whole-host GPUs; avoid presenting an ordinary engine command as a complete P/D command.
- [x] Show selected scalar presets for users uploading the shared ZIP manually; RMS links prefill them without changing packaged defaults.

## Phase 3 — validation
- [x] Run executable report regressions for switching, keyboard focus, filtering, safe links, preset preservation and unavailable reasons.
- [x] Exercise the actual report in a browser at desktop and mobile widths, including P/D selection and missing-capacity explanation.
- [x] Prepare and commit the isolated UI change for parent integration.

Validation: all 29 executable report checks pass. Actual headed Chromium rendered the fixture report, switched combined/P/D tabs with mouse and keyboard, showed role counts/AD capacity, and expanded the manual ZIP preset panel. Desktop and 390px mobile screenshots were visually inspected; document width equalled the 390px viewport, with no horizontal page overflow. Missing-eligibility/capacity paths have executable coverage. Browser evidence is under `/tmp/discovery-layout-tabs-preview/.playwright-cli`; the only console error was a missing local favicon. This is report UI validation, not GPU or live RMS launch validation.
