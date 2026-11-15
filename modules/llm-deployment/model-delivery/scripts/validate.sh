#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
source runtime/common.sh
model_inputs
model_geometry
model_platform_ready
model_validate
jq --slurpfile allocation model-allocation-check.json --slurpfile platform platform-readiness.json '.+{allocation_check:$allocation[0],shared_controller_checks:$platform[0]}' model-validation.json > model-validation-evidence.json
mv model-validation-evidence.json model-validation.json
echo 'Model validation result:'
cat model-validation.json
