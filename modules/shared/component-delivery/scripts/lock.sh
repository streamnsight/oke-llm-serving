#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# A Lease serializes all managed operations for a cluster/namespace/release.
# Expiry alone NEVER permits takeover: native Helm cannot renew between stages.
lock_read() {
  kubectl -n "${lock_namespace:-kube-system}" get lease "$lock_name" --ignore-not-found -o json > lease.json
}
lock_assert() {
  lock_read
  jq -e --arg holder "$OCI_DEPLOYMENT_ID" --arg owner "$owner" \
    '.spec.holderIdentity == $holder and .metadata.annotations["oke-llm/owner-token"] == $owner' lease.json >/dev/null
}
lock_acquire() {
  local now old_holder old_state expires
  now=$(date -u +%s)
  jq -n --arg namespace "${lock_namespace:-kube-system}" --arg name "$lock_name" --arg owner "$owner" --arg holder "$OCI_DEPLOYMENT_ID" --argjson now "$now" --argjson duration "$lock_duration" \
    '{apiVersion:"coordination.k8s.io/v1",kind:"Lease",metadata:{name:$name,namespace:$namespace,annotations:{"oke-llm/owner-token":$owner,"oke-llm/acquired-epoch":($now|tostring)}},spec:{holderIdentity:$holder,leaseDurationSeconds:$duration}}' > new-lease.json
  if kubectl create -f new-lease.json >/dev/null 2> lease-create-error.txt; then lock_held=true; return; fi
  # Any permissions/transport failure here fails closed, never overwrites blindly.
  lock_read
  jq -e --arg owner "$owner" '.metadata.annotations["oke-llm/owner-token"] == $owner' lease.json >/dev/null
  # Preserve trailing newlines in the observed holder; command substitution
  # would otherwise strip them and can turn an occupied Lease into a blank ID.
  old_holder=$(jq -er '(.spec.holderIdentity // "") + "."' lease.json)
  old_holder=${old_holder%.}
  if [[ -n $old_holder ]]; then
    [[ ${RECOVER_LOCK_HOLDER:-} == "$old_holder" ]] || {
      printf 'Component Lease %s/%s is held (holderIdentity=%s); explicit stale recovery required.\n' \
        "${lock_namespace:-kube-system}" "$lock_name" "$(jq -c '.spec.holderIdentity' lease.json)" >&2
      return 2
    }
    expires=$(jq -er '(.metadata.annotations["oke-llm/acquired-epoch"]|tonumber)+.spec.leaseDurationSeconds' lease.json)
    (( now > expires )) || { echo "Lock has not expired; refusing recovery" >&2; return 2; }
    old_state=$(oci devops deployment get --deployment-id "$old_holder" --query 'data."lifecycle-state"' --raw-output)
    case "$old_state" in SUCCEEDED|FAILED|CANCELED) ;; *) echo "Prior deployment is not terminal: $old_state" >&2; return 2;; esac
  fi
  # Kubernetes resourceVersion is a compare-and-swap precondition. Only one
  # simultaneous contender can replace the same observed lease revision.
  jq --slurpfile previous lease.json '.metadata.resourceVersion = $previous[0].metadata.resourceVersion' new-lease.json > replacement-lease.json
  kubectl replace -f replacement-lease.json >/dev/null
  lock_held=true
}
lock_release() {
  lock_assert || return
  jq '.spec.holderIdentity=""' lease.json > released-lease.json
  kubectl replace -f released-lease.json >/dev/null
  lock_held=false
}
