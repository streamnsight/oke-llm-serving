#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
source runtime/common.sh
model_inputs
model_platform_ready
model_validate
oci artifacts generic artifact upload-by-path --repository-id "$DELIVERY_RESULT_REPOSITORY" \
  --artifact-path "$identity/model/$DELIVERY_GENERATION/$OCI_DEPLOYMENT_ID/validation.json" \
  --artifact-version "$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}" --content-body model-validation.json >/dev/null
