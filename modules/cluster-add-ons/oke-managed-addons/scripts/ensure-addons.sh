#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
set +x
umask 077
exec 3>&1
phase=initialization
scratch=''
finish() {
  local code=$?
  # A failing CLI call can still have stdout/stderr redirected into a scratch
  # file when Bash invokes EXIT. Keep diagnostics on the original RMS stream.
  if (( code != 0 )); then printf 'OKE add-on helper failed while %s (exit %s).\n' "$phase" "$code" >&3; fi
  if [[ -n "$scratch" ]]; then rm -rf "$scratch"; fi
  exit "$code"
}
trap finish EXIT
: "${CLUSTER_ID:?}" "${REGION:?}" "${REQUIRES_RDMA:?}" "${INSTALL_GPU_HEALTH:?}" "${SUPPORTED_ADDONS_JSON:?}"
for tool in oci jq; do command -v "$tool" >/dev/null || { echo "Add-on installation requires $tool." >&2; exit 2; }; done
scratch=$(mktemp -d)
phase='configuring OCI authentication'
setting() { local key value; for key in "TF_VAR_$1" "OCI_$1" "$1"; do value=${!key:-}; if [[ -n "$value" ]]; then printf '%s' "$value"; return; fi; done; }
auth_args=()
mode=${TF_VAR_auth:-${OCI_AUTH:-}}
case "$mode" in
  InstancePrincipal|instance_principal)
    case "$(setting use_obo_token)" in
      true)
        token_path=$(setting obo_token_path)
        if [[ -z "$token_path" ]]; then
          token=$(setting obo_token)
          [[ -n "$token" ]] || { echo 'RMS delegated authentication requires its caller token.' >&2; exit 2; }
          token_path="$scratch/caller-token"; printf '%s' "$token" > "$token_path"; unset token
        fi
        [[ -r "$token_path" && -s "$token_path" ]] || { echo 'Cannot read RMS delegated caller token.' >&2; exit 2; }
        printf '[DEFAULT]\ndelegation_token_file=%s\n' "$token_path" > "$scratch/cli-config"
        auth_args=(--auth instance_obo_user --config-file "$scratch/cli-config" --profile DEFAULT)
        ;;
      false|'') auth_args=(--auth instance_principal);;
      *) echo 'use_obo_token must be true or false' >&2; exit 2;;
    esac;;
  ResourcePrincipal|resource_principal) auth_args=(--auth resource_principal);;
  APIKey|api_key) auth_args=(--auth api_key);;
  '') if [[ -n ${OCI_RESOURCE_PRINCIPAL_VERSION:-} && -z ${OCI_CLI_AUTH:-} ]]; then auth_args=(--auth resource_principal); fi;;
  *) echo 'Unsupported provider authentication mode for OKE add-on installation.' >&2; exit 2;;
esac
cli() { oci ${auth_args[@]+"${auth_args[@]}"} --region "$REGION" --output json --connection-timeout 10 --read-timeout 60 "$@"; }
phase='detecting supported OCI CLI add-on commands'
if cli ce addon list --help >/dev/null 2>&1; then
  addon_list=(ce addon list)
  addon_install=(ce addon install)
  addon_get=(ce addon get)
elif cli ce cluster list-addons --help >/dev/null 2>&1; then
  addon_list=(ce cluster list-addons)
  addon_install=(ce cluster install-addon)
  addon_get=(ce cluster get-addon)
else
  echo 'This OCI CLI supports neither ce addon list nor ce cluster list-addons.' >&2
  exit 2
fi
printf 'OKE add-on helper: OCI CLI %s; using %s.\n' "$(oci --version 2>/dev/null || printf unknown)" "${addon_list[*]}"
refresh() {
  phase='reading OKE add-on inventory'
  cli "${addon_list[@]}" --cluster-id "$CLUSTER_ID" --all > "$scratch/inventory.json"
  jq -e '.data | (if type == "array" then . elif type == "object" then .items else null end) |
    if type == "array" then map(. + {"addon-name": (.name // ."addon-name")}) else error("Expected add-on inventory") end' "$scratch/inventory.json" > "$scratch/addons.json"
}
lookup() { jq -c --arg name "$1" '[.[] | select(."addon-name" == $name and ."lifecycle-state" != "DELETED")] | if length > 1 then error("Duplicate add-on") else .[0] // {} end' "$scratch/addons.json"; }
ensure() {
  local name=$1 addon state attempt requested=false
  for attempt in $(seq 1 120); do
    refresh
    phase="inspecting OKE add-on $name"
    addon=$(lookup "$name")
    state=$(jq -r '."lifecycle-state" // "MISSING"' <<< "$addon")
    case "$state" in
      ACTIVE) echo "Reuse ACTIVE OKE add-on: $name (settings preserved)."; return;;
      CREATING|UPDATING|DELETING) sleep 10;;
      MISSING)
        if [[ "$requested" == true ]]; then sleep 10; continue; fi
        jq -e --arg name "$name" 'index($name) != null' <<< "$SUPPORTED_ADDONS_JSON" >/dev/null || {
          echo "No ACTIVE compatible OKE add-on option for $name." >&2; return 1;
        }
        echo "Enable OKE add-on: $name (service-selected compatible version)."
        # Never override an existing installation, including one enabled concurrently.
        phase="enabling OKE add-on $name"
        if ! cli "${addon_install[@]}" --cluster-id "$CLUSTER_ID" --addon-name "$name" --is-override-existing false > "$scratch/install.json" 2> "$scratch/install.err"; then
          refresh
          phase="enabling OKE add-on $name"
          [[ $(lookup "$name" | jq -r '."lifecycle-state"') == ACTIVE ]] || { cat "$scratch/install.err" >&2; return 1; }
        fi
        requested=true
        sleep 10;;
      *) echo "OKE add-on $name is $state; repair it explicitly. Existing configuration was preserved." >&2; return 1;;
    esac
  done
  echo "Timed out waiting for OKE add-on $name to become ACTIVE." >&2
  return 1
}
ensure NodeFeatureDiscovery
refresh
# Preserve either existing GPU integration, including an explicitly disabled
# Operator device plugin paired with an ACTIVE standalone plugin.
gpu=$(jq -c '[.[] | select(."addon-name" == "NvidiaGpuOperator" or ."addon-name" == "NvidiaDevicePlugin" or ."addon-name" == "NvidiaGpuPlugin") | select(."lifecycle-state" != "DELETED")]' "$scratch/addons.json")
if [[ $(jq length <<< "$gpu") == 0 ]]; then
  if jq -e 'index("NvidiaGpuOperator") != null' <<< "$SUPPORTED_ADDONS_JSON" >/dev/null; then
    ensure NvidiaGpuOperator
  else
    ensure NvidiaDevicePlugin
  fi
else
  while IFS= read -r name; do ensure "$name"; done < <(jq -r '.[]."addon-name"' <<< "$gpu")
fi
refresh
if jq -e 'any(.[]; ."addon-name" == "NvidiaGpuOperator")' "$scratch/addons.json" >/dev/null; then
  # ListAddons returns summaries without configurations; GetAddon is needed to
  # distinguish an explicitly disabled device plugin from its enabled default.
  phase='reading NVIDIA GPU Operator configuration'
  cli "${addon_get[@]}" --cluster-id "$CLUSTER_ID" --addon-name NvidiaGpuOperator > "$scratch/operator.json"
  jq --slurpfile operator "$scratch/operator.json" 'map(if ."addon-name" == "NvidiaGpuOperator" then . + {configurations: ($operator[0].data.configurations // [])} else . end)' "$scratch/addons.json" > "$scratch/with-configurations.json"
  mv "$scratch/with-configurations.json" "$scratch/addons.json"
fi
phase='validating the NVIDIA device plugin'
jq -e 'any(.[]; ."lifecycle-state" == "ACTIVE" and
  ((."addon-name" == "NvidiaDevicePlugin" or ."addon-name" == "NvidiaGpuPlugin") or
   (."addon-name" == "NvidiaGpuOperator" and (any(.configurations[]?; .key == "devicePlugin.enabled" and (.value | ascii_downcase) == "false") | not))))' "$scratch/addons.json" >/dev/null || {
  echo 'No usable ACTIVE NVIDIA device plugin. Existing disabled settings were preserved; enable devicePlugin.enabled before retrying.' >&2; exit 1;
}
if [[ "$REQUIRES_RDMA" == true ]]; then ensure NvidiaNetworkOperator; fi
if [[ "$INSTALL_GPU_HEALTH" == true ]]; then ensure GpuHealthMonitoring; fi
echo 'OKE add-ons enabled. GPU/CUDA/RDMA runtime and GPU health policy readiness require live node validation.'
