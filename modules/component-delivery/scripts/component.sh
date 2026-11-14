#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
umask 077
# OCI documents these as predefined command-spec variables. Explicit env
# bindings also carry them into the child script when they are not exported by
# the runner's parent shell. A per-stage random fallback would break the lock.
export OCI_DEPLOYMENT_ID="${OCI_DEPLOYMENT_ID:-${DELIVERY_DEPLOYMENT_ID:-}}"
export OCI_PIPELINE_ID="${OCI_PIPELINE_ID:-${DELIVERY_PIPELINE_ID:-}}"
[[ -n $OCI_DEPLOYMENT_ID && $OCI_DEPLOYMENT_ID != *'${'* ]] || {
  echo 'OCI Shell did not supply its predefined OCI_DEPLOYMENT_ID; refusing an uncorrelated component operation.' >&2; exit 2;
}
: "${DELIVERY_OPERATION:?}" "${DELIVERY_GENERATION:?}" "${DELIVERY_RESULT_REPOSITORY:?}"
source ./lock.sh
source ./tools.sh
cluster=$(jq -er .cluster_id specification.json)
namespace=$(jq -er .namespace specification.json)
release=$(jq -er .release_name specification.json)
component=$(jq -er .component specification.json)
platform=$(jq -er .platform specification.json)
owner=$(jq -er .ownership_token specification.json)
lock_name=$(jq -er .lock_name specification.json)
lock_duration=$(jq -er .lock_duration_seconds specification.json)
timeout=$(jq -er .timeout_seconds specification.json)
owner_name="oke-llm-owner-$(printf '%s' "$namespace/$release" | sha256sum | cut -c1-24)"
settings_sha256=$(jq -cn --slurpfile specification specification.json \
  '((($specification[0].parameters|keys)+["CHART_VERSION"])|map(. as $key|{key:$key,value:env[$key]})|from_entries)' | sha256sum | cut -d' ' -f1)
lock_held=false
keep_lock=false
status=failed
helm_revision=""
result_uploaded=false
message="Operation did not complete"

evidence() {
  local code=$1 version
  jq -n --arg status "$status" --arg message "$message" --arg operation "$DELIVERY_OPERATION" --arg generation "$DELIVERY_GENERATION" \
    --arg component "$component" --arg cluster "$cluster" --arg namespace "$namespace" --arg release "$release" \
    --arg deployment "$OCI_DEPLOYMENT_ID" --arg pipeline "${OCI_PIPELINE_ID:-}" --arg settings_sha256 "$settings_sha256" --arg helm_revision "$helm_revision" --arg checked_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson exit_code "$code" --slurpfile specification specification.json \
    '{schema_version:"1.0",status:$status,message:$message,operation:$operation,generation:$generation,component:$component,cluster_id:$cluster,namespace:$namespace,release_name:$release,deployment_id:$deployment,pipeline_id:$pipeline,checked_at:$checked_at,exit_code:$exit_code,settings_sha256:$settings_sha256,helm_revision:($helm_revision|if .=="" then null else tonumber end),effective_parameters:((($specification[0].parameters|keys)+["CHART_VERSION"])|map(. as $key|{key:$key,value:env[$key]})|from_entries)}' > result.json
  version="$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}-${RANDOM}"
  oci artifacts generic artifact upload-by-path --repository-id "$DELIVERY_RESULT_REPOSITORY" \
    --artifact-path "$platform/components/$component/$DELIVERY_GENERATION/$OCI_DEPLOYMENT_ID/$DELIVERY_OPERATION.json" \
    --artifact-version "$version" --content-body result.json >/dev/null
  result_uploaded=true
}
finish() {
  local code=$?
  trap - EXIT
  if (( code != 0 )); then status=failed; result_uploaded=false; fi
  if [[ $result_uploaded != true ]]; then evidence "$code" || code=1; fi
  # A failed native stage never reaches finish; its lock remains deliberately.
  # Shell failures before Helm or after it can safely release their own lock.
  if [[ $lock_held == true && $keep_lock != true ]]; then lock_release || code=1; fi
  exit "$code"
}
trap finish EXIT
delivery_tools

release_read() {
  helm list --namespace "$namespace" --all --filter "^${release}$" -o json > releases.json
  jq -e 'type=="array"' releases.json >/dev/null
}
owner_assert() {
  kubectl -n "$namespace" get configmap "$owner_name" -o json > owner.json
  jq -e --arg owner "$owner" '.data.ownership_token == $owner' owner.json >/dev/null
}
owner_write() {
  local phase=$1
  jq -n --arg name "$owner_name" --arg ns "$namespace" --arg owner "$owner" --arg generation "$DELIVERY_GENERATION" --arg phase "$phase" \
    --arg deployment "$OCI_DEPLOYMENT_ID" --arg version "$CHART_VERSION" --arg settings_sha256 "$settings_sha256" --arg helm_revision "$helm_revision" \
    '{apiVersion:"v1",kind:"ConfigMap",metadata:{name:$name,namespace:$ns,labels:{"app.kubernetes.io/managed-by":"oke-llm-serving"}},data:{ownership_token:$owner,generation:$generation,status:$phase,deployment_id:$deployment,chart_version:$version,settings_sha256:$settings_sha256,helm_revision:$helm_revision}}' > owner-update.json
  kubectl apply -f owner-update.json >/dev/null
}
dependencies_ready() {
  local dep_namespace dep_release
  while IFS=$'\t' read -r dep_namespace dep_release; do
    helm status "$dep_release" -n "$dep_namespace" -o json | jq -e '.info.status=="deployed"' >/dev/null
  done < <(jq -r '.dependencies[]|[.namespace,.release_name]|@tsv' specification.json)
}
validate_release() {
  local crd deployment
  helm status "$release" -n "$namespace" -o json > helm-status.json
  jq -e '.info.status=="deployed"' helm-status.json >/dev/null
  helm_revision=$(jq -er '.version | select(type=="number" and .>0) | tostring' helm-status.json)
  while IFS= read -r crd; do kubectl wait --for=condition=Established "crd/$crd" --timeout="${timeout}s"; done < <(jq -r '.crd_names[]' specification.json)
  while IFS= read -r deployment; do kubectl -n "$namespace" rollout status "deployment/$deployment" --timeout="${timeout}s"; done < <(jq -r '.deployment_names[]' specification.json)
}
retention_guard() {
  # Helm reads retention annotations from release manifests, so patching only
  # the live CRD before uninstall is insufficient. Refuse unsafe manifests.
  yq eval-all -o=json -I=0 '.' "$1" > retained-resources.jsonl
  jq -s -e 'def flatten_resources: if .kind=="List" then .items[]|flatten_resources else . end; [.[]|select(type=="object")|flatten_resources|select(.kind=="CustomResourceDefinition" or .kind=="PersistentVolumeClaim")] | all(.[]; .metadata.annotations["helm.sh/resource-policy"] == "keep")' retained-resources.jsonl >/dev/null || {
    message="Chart contains a templated CRD or PVC without Helm keep retention; refusing unsafe lifecycle"; return 2;
  }
}
crds_update() {
  local crd name
  local archives=(upstream/*.tgz)
  helm show crds "${archives[0]}" > crd-bundle.yaml
  yq eval-all -o=json -I=0 'select(.kind == "CustomResourceDefinition")' crd-bundle.yaml > crds.jsonl
  while IFS= read -r crd; do
    name=$(jq -er '.metadata.name' <<< "$crd")
    kubectl get crd "$name" --ignore-not-found -o json > existing-crd.json
    jq --arg owner "$owner" '.metadata.annotations["oke-llm/owner-token"]=$owner | .metadata.annotations["helm.sh/resource-policy"]="keep"' <<< "$crd" > managed-crd.json
    if [[ -s existing-crd.json ]]; then
      jq -e --arg owner "$owner" '.metadata.annotations["oke-llm/owner-token"]==$owner' existing-crd.json >/dev/null || {
        message="Existing CRD $name is externally owned; choose reuse or resolve ownership explicitly"; return 2;
      }
      kubectl apply --server-side --field-manager=oke-llm-serving-crds -f managed-crd.json >/dev/null
    else
      # Atomic create must fail if another owner created it after our read.
      kubectl create --field-manager=oke-llm-serving-crds -f managed-crd.json >/dev/null
    fi
    kubectl wait --for=condition=Established "crd/$name" --timeout="${timeout}s"
  done < crds.jsonl
}
uninstall_consumers_guard() {
  local kind
  # Missing APIs have no instances. Discovery/read errors are never treated as
  # an empty result. Compare exact identities, not user-changeable labels.
  kubectl api-resources --verbs=list -o name > served-resources.txt
  yq eval-all -o=json -I=0 '.' release-manifest.yaml > release-documents.jsonl
  jq -s 'map(select(type=="object")) | map(if .kind=="List" then .items[] else . end)' release-documents.jsonl > release-objects.json
  while IFS= read -r kind; do
    grep -Fxq "$kind" served-resources.txt || continue
    kubectl get "$kind" --all-namespaces -o json > blockers.json
    jq -e --slurpfile owned release-objects.json --arg ns "$namespace" \
      '[.items[] | . as $instance | select(any($owned[0][]; .apiVersion==$instance.apiVersion and .kind==$instance.kind and .metadata.name==$instance.metadata.name and (.metadata.namespace // $ns)==($instance.metadata.namespace // $ns)) | not)] | length==0' blockers.json >/dev/null || {
      message="External dependent resources remain for $kind"; return 2;
    }
  done < <(jq -r '.blocker_kinds[]' specification.json)
}
render_values() {
  # Reproduce DevOps textual placeholder replacement before validating the
  # actual values and chart. Parameter data is never evaluated as Shell code.
  jq -r '.values_yaml' specification.json > values-template.yaml
  jq -r --rawfile template values-template.yaml \
    'reduce ((.parameters|keys)+["CHART_VERSION"])[] as $key ($template; split("${"+$key+"}")|join(env[$key]))' specification.json > effective-values.yaml
  yq -e 'tag == "!!map"' effective-values.yaml >/dev/null
  ! grep -Eq '\$\{[A-Za-z_][A-Za-z0-9_]*\}' effective-values.yaml || { message="Unresolved values placeholder"; return 2; }
}
mirror_chart() {
  local repository chart mirror archive token existing
  repository=$(jq -er .chart.repository specification.json)
  chart=$(jq -er .chart.name specification.json)
  mirror=$(jq -er .mirror_url specification.json)
  [[ $CHART_VERSION =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([+-][A-Za-z0-9.-]+)?$ ]] || { message="CHART_VERSION must be an explicit semantic version"; return 2; }
  mkdir -p upstream mirrored
  if [[ $repository == oci://* ]]; then
    helm pull "${repository%/}/$chart" --version "$CHART_VERSION" --destination upstream
  else
    helm pull "$chart" --repo "$repository" --version "$CHART_VERSION" --destination upstream
  fi
  local archives=(upstream/*.tgz)
  [[ ${#archives[@]} == 1 && -f ${archives[0]} ]] || return 2
  archive=${archives[0]}
  [[ $(helm show chart "$archive" | yq -r .name) == "$chart" ]] || { message="Upstream chart name mismatch"; return 2; }
  helm template "$release" "$archive" --namespace "$namespace" --values effective-values.yaml > rendered-chart.yaml
  retention_guard rendered-chart.yaml
  token=$(oci raw-request --http-method GET --target-uri "https://$DELIVERY_REGISTRY_HOST/20180419/docker/token" --query data.token --raw-output)
  [[ -n $token && $token != null ]] || return 2
  printf '%s' "$token" | helm registry login "$DELIVERY_REGISTRY_HOST" --username BEARER_TOKEN --password-stdin
  unset token
  if helm pull "$mirror" --version "$CHART_VERSION" --destination mirrored 2> mirror-pull-error.txt; then
    local copies=(mirrored/*.tgz)
    [[ ${#copies[@]} == 1 && -f ${copies[0]} ]] || return 2
    existing=${copies[0]}
    [[ $(sha256sum "$archive" | cut -d' ' -f1) == "$(sha256sum "$existing" | cut -d' ' -f1)" ]] || { message="Mirrored version differs from upstream; refusing overwrite"; return 2; }
  else
    # An unreadable mirror does not authorize an overwrite. Only an explicit
    # registry not-found response permits initial publication.
    grep -Eqi 'not found|manifest_unknown|404' mirror-pull-error.txt || { cat mirror-pull-error.txt >&2; return 2; }
    helm push "$archive" "${mirror%/*}"
  fi
}

case "$DELIVERY_OPERATION" in
  prepare)
    lock_acquire
    dependencies_ready
    release_read
    if [[ $(jq length releases.json) != 0 ]]; then owner_assert; fi
    # Existing orphaned ownership must also match before a first/retry install.
    kubectl -n "$namespace" get configmap "$owner_name" --ignore-not-found -o json > existing-owner.json
    if [[ -s existing-owner.json ]]; then jq -e --arg owner "$owner" '.data.ownership_token==$owner' existing-owner.json >/dev/null; fi
    render_values
    mirror_chart
    kubectl create namespace "$namespace" --dry-run=client -o json | kubectl apply -f - >/dev/null
    owner_write applying
    crds_update
    status=prepared; message="Owned native Helm upgrade may proceed"
    evidence 0
    keep_lock=true
    ;;
  finish)
    lock_assert
    lock_held=true
    owner_assert
    jq -e --arg generation "$DELIVERY_GENERATION" --arg deployment "$OCI_DEPLOYMENT_ID" --arg settings "$settings_sha256" \
      '.data.generation==$generation and .data.deployment_id==$deployment and .data.settings_sha256==$settings' owner.json >/dev/null || {
      message="Finish arguments differ from the lock-owning prepare stage"; exit 2;
    }
    dependencies_ready
    validate_release
    jq -e --arg version "${CHART_VERSION#v}" --arg chart "$(jq -er .chart.name specification.json)" \
      '.chart.metadata.name==$chart and (.chart.metadata.version|ltrimstr("v"))==$version' helm-status.json >/dev/null || {
      message="Installed chart does not match the prepared chart/version"; exit 2;
    }
    render_values
    yq -o=json effective-values.yaml | jq -S '. // {}' > expected-values.json
    helm get values "$release" -n "$namespace" -o json | jq -S '. // {}' > installed-values.json
    cmp -s expected-values.json installed-values.json || { message="Installed Helm values differ from the prepared arguments"; exit 2; }
    status=ready; message="Helm release and declared controllers validated"
    evidence 0
    owner_write ready
    ;;
  reuse)
    dependencies_ready
    validate_release
    status=ready; message="External release validated without install, ownership adoption or uninstall"
    ;;
  undeploy)
    [[ ${CONFIRM_UNINSTALL:-false} == true ]] || { message="Explicit CONFIRM_UNINSTALL=true required"; exit 2; }
    lock_acquire
    release_read
    if [[ $(jq length releases.json) != 0 ]]; then
      owner_assert
      helm get manifest "$release" -n "$namespace" > release-manifest.yaml
      retention_guard release-manifest.yaml
      uninstall_consumers_guard
      owner_write retiring
      helm uninstall "$release" --namespace "$namespace" --wait --timeout "${timeout}s"
      owner_write retired
    fi
    status=retired; message="Owned release absent; namespace, CRDs, data and GPU nodes retained"
    ;;
  *) message="Unknown fixed delivery operation"; exit 2;;
esac
