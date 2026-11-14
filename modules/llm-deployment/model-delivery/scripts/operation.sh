#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
umask 077
export OCI_DEPLOYMENT_ID="${OCI_DEPLOYMENT_ID:-${DELIVERY_DEPLOYMENT_ID:-}}"
export OCI_PIPELINE_ID="${OCI_PIPELINE_ID:-${DELIVERY_PIPELINE_ID:-}}"
[[ -n $OCI_DEPLOYMENT_ID && $OCI_DEPLOYMENT_ID != *'${'* ]] || { echo 'Missing OCI deployment identity' >&2; exit 2; }
source runtime/common.sh
source runtime/lock.sh
source runtime/tools.sh
lock_name="oke-llm-$(printf '%s' "$cluster/$namespace/$release" | sha256sum | cut -c1-40)"
lock_namespace=$namespace
lock_duration=$((3 * timeout + 1800))
lock_held=false
status=failed
operation_cleanup() {
  local code=$?
  trap - EXIT
  jq -n --arg status "$status" --arg operation "$DELIVERY_OPERATION" --arg generation "$DELIVERY_GENERATION" --arg deployment "$OCI_DEPLOYMENT_ID" --arg namespace "$namespace" --arg release "$release" --argjson exit_code "$code" \
    '{status:$status,operation:$operation,generation:$generation,deployment_id:$deployment,namespace:$namespace,release:$release,exit_code:$exit_code}' > operation-result.json
  oci artifacts generic artifact upload-by-path --repository-id "$DELIVERY_RESULT_REPOSITORY" --artifact-path "$identity/model/$DELIVERY_GENERATION/$OCI_DEPLOYMENT_ID/$DELIVERY_OPERATION.json" --artifact-version "$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}" --content-body operation-result.json >/dev/null || code=1
  if [[ $lock_held == true ]]; then lock_release || code=1; fi
  exit "$code"
}
trap operation_cleanup EXIT
delivery_tools
model_inputs
model_geometry
model_platform_ready
lock_acquire
model_ready_owner
case "$DELIVERY_OPERATION" in
  validate) bash runtime/validate.sh;;
  benchmark) bash runtime/benchmark.sh;;
  *) model_fail 'Unknown fixed model operation';;
esac
status=ready
