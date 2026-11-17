<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Dedicated undeploy defaults

The explicit undeploy pipeline is the user's operation selection. Its CONFIRM_UNINSTALL default should be true; other pipelines retain false. Preserve explicit false overrides and existing ownership, locking, dependency and retention checks.

1. [x] Reproduce the false-default defect with an executable Terraform assertion, then change only operation-specific pipeline defaults and user-facing instructions.
2. [x] Run focused Terraform and Shell lifecycle regressions, commit the change, and validate the committed release archive with Terraform 1.5.7.
3. [ ] Check the failed model's existing undeploy default and update only if needed, without running it. Refresh discovery source/bundles through a reviewed publication-only plan. Record validation, merge into main and rebuild.

The new Terraform assertion failed against the old code (2 passed, 1 failed), then all 3 component-delivery Terraform tests passed with operation-specific defaults. The existing model undeploy pipeline was inspected and already has CONFIRM_UNINSTALL=true; it was not changed or executed. Shell lifecycle tests passed (21 passed; one optional fixture skipped). Release/live publication validation is in progress. Updating a pipeline default does not authorize executing uninstall or changing GPU allocations.
