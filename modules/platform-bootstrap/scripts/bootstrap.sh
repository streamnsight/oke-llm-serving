#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Platform-only DevOps Shell runner: never deploys a model or changes node pools.
set -euo pipefail
for tool in jq curl tar sha256sum oci; do command -v "$tool" >/dev/null || { echo "Missing DevOps tool: $tool" >&2; exit 2; }; done
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
run_dir=$(mktemp -d)
trap 'rm -rf "$run_dir"' EXIT
cd "$run_dir"
jq -n -f "$script_dir/config.jq" > effective.json
jq .config effective.json > config.json
settings_hash=$(printf '%s' "$(jq -cS .settings effective.json)" | sha256sum | cut -d ' ' -f 1)
platform=$(jq -er .platform_name config.json)
region=$(jq -er .region config.json)
generation=$PLATFORM_GENERATION
bucket=$(jq -er .artifact_bucket config.json)
storage_namespace=$(jq -er .storage_namespace config.json)
prefix=$EVIDENCE_PREFIX
configuration_status=original
if [[ "$settings_hash" != "$EXPECTED_SETTINGS_SHA256" ]]; then
  configuration_status=overridden
  generation=$(printf '%s:%s' "$PLATFORM_GENERATION" "$settings_hash" | sha256sum | cut -d ' ' -f 1)
  prefix="$prefix/overrides/$settings_hash"
fi
export OCI_CLI_AUTH=resource_principal OCI_CLI_REGION="$region"
put() { oci os object put --namespace-name "$storage_namespace" --bucket-name "$bucket" --name "$1" --file "$2" --force >/dev/null; }
archive() {
  local code=$?
  trap - EXIT
  jq -n --arg generation "$generation" --arg platform "$platform" --arg checked_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg deployment_id "${OCI_DEPLOYMENT_ID:-}" --argjson code "$code" \
    --arg desired_generation "$PLATFORM_GENERATION" --arg configuration_status "$configuration_status" --arg mode "$PLATFORM_MODE" \
    --slurpfile effective effective.json --slurpfile checks node-readiness.json --slurpfile controllers controllers.json \
    '{generation:$generation,platform_name:$platform,checked_at:$checked_at,deployment_id:$deployment_id,status:(if $code==0 then "ready" else "failed" end),exit_code:$code,desired_generation:$desired_generation,configuration_status:$configuration_status,settings:$effective[0].settings,pipeline_mode:$mode,validation_scope:$checks[0].validation_scope,node_checks:$checks[0],controllers:$controllers[0],model_runtime_validation:"not_run",rdma_fabric_validation:"not_run"}' > readiness.json
  # Retain per-run evidence; only the pipeline owns the generation readiness key.
  local run_id=${OCI_DEPLOYMENT_ID:-$(date -u +%Y%m%dT%H%M%SZ)}
  for file in readiness.json gpu-nodes.json cpu-nodes.json helm-releases.json lws-admission.json effective.json; do
    [[ ! -s "$file" ]] || put "$prefix/runs/$run_id/$file" "$file" || code=1
  done
  if [[ "$code" != 0 ]]; then jq '.status="failed"' readiness.json > failed.json; mv failed.json readiness.json; fi
  put "$prefix/readiness.json" readiness.json || code=1
  echo "Platform evidence: oci://$region/$storage_namespace/$bucket/$prefix/readiness.json"
  rm -rf "$run_dir"
  exit "$code"
}
printf '{}\n' > node-readiness.json
printf '{}\n' > controllers.json
trap archive EXIT
jq -n --arg generation "$generation" '{generation:$generation,status:"in_progress"}' > readiness.json
put "$prefix/readiness.json" readiness.json
mkdir bin
export PATH="$run_dir/bin:$PATH"
kube_version=$(jq -er .target.kubernetes_version config.json)
curl -fsSL --retry 3 "https://dl.k8s.io/release/$kube_version/bin/linux/amd64/kubectl" -o bin/kubectl
curl -fsSL --retry 3 "https://dl.k8s.io/release/$kube_version/bin/linux/amd64/kubectl.sha256" -o kubectl.sha256
printf '%s  bin/kubectl\n' "$(cat kubectl.sha256)" | sha256sum -c -
chmod +x bin/kubectl
helm_version=$(jq -er .components.helm_version config.json)
curl -fsSL --retry 3 "https://get.helm.sh/helm-$helm_version-linux-amd64.tar.gz" -o helm.tgz
curl -fsSL --retry 3 "https://get.helm.sh/helm-$helm_version-linux-amd64.tar.gz.sha256sum" -o helm.sha256
printf '%s  helm.tgz\n' "$(cut -d ' ' -f 1 helm.sha256)" | sha256sum -c -
tar -xzf helm.tgz
mv linux-amd64/helm bin/helm
oci ce cluster create-kubeconfig --cluster-id "$(jq -er .cluster_id config.json)" --file "$run_dir/kubeconfig" --region "$region" --token-version 2.0.0 --kube-endpoint PRIVATE_ENDPOINT >/dev/null
export KUBECONFIG="$run_dir/kubeconfig"
ready=false
for attempt in $(seq 1 120); do
  if [[ $(jq -r '.gpu_allocation_enabled != false' config.json) == true ]]; then
    kubectl get nodes -l "oke-llm/allocation=$platform" -o json > gpu-nodes.json
  else
    printf '{"items":[]}\n' > gpu-nodes.json
  fi
  kubectl get nodes -o json > cpu-nodes.json
  jq -n --slurpfile c config.json --slurpfile gpu gpu-nodes.json --slurpfile cpu cpu-nodes.json '{config:$c[0],gpu_nodes:$gpu[0],cpu_nodes:$cpu[0]}' | jq -f "$script_dir/readiness.jq" > node-readiness.json
  if jq -e .ready node-readiness.json >/dev/null; then ready=true; break; fi
  if jq -e .fatal node-readiness.json >/dev/null; then break; fi
  sleep 10
done
[[ "$ready" == true ]] || { jq -r '.reasons[]' node-readiness.json >&2; exit 1; }
source "$script_dir/lws.sh"
