#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Platform-only DevOps Shell runner: never deploys a model or changes node pools.
set -euo pipefail
for tool in jq curl tar sha256sum oci; do command -v "$tool" >/dev/null || { echo "Missing DevOps tool: $tool" >&2; exit 2; }; done
run_dir=$(mktemp -d)
cd "$run_dir"
printf '%s' "$CONFIG_B64" | base64 --decode > config.json
printf '%s' "$READINESS_B64" | base64 --decode > readiness.jq
platform=$(jq -er .platform_name config.json)
region=$(jq -er .region config.json)
generation=$(jq -er .generation config.json)
bucket=$(jq -er .artifact_bucket config.json)
storage_namespace=$(jq -er .storage_namespace config.json)
prefix=$(jq -er .evidence_prefix config.json)
export OCI_CLI_AUTH=resource_principal OCI_CLI_REGION="$region"
put() { oci os object put --namespace-name "$storage_namespace" --bucket-name "$bucket" --name "$1" --file "$2" --force >/dev/null; }
archive() {
  local code=$?
  trap - EXIT
  jq -n --arg generation "$generation" --arg platform "$platform" --arg checked_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg deployment_id "${OCI_DEPLOYMENT_ID:-}" --argjson code "$code" \
    --slurpfile checks node-readiness.json --slurpfile controllers controllers.json \
    '{generation:$generation,platform_name:$platform,checked_at:$checked_at,deployment_id:$deployment_id,status:(if $code==0 then "ready" else "failed" end),exit_code:$code,node_checks:$checks[0],controllers:$controllers[0],model_runtime_validation:"not_run",rdma_fabric_validation:"not_run"}' > readiness.json
  # Retain per-run evidence; only the pipeline owns the generation readiness key.
  local run_id=${OCI_DEPLOYMENT_ID:-$(date -u +%Y%m%dT%H%M%SZ)}
  for file in readiness.json gpu-nodes.json cpu-nodes.json helm-releases.json lws-admission.json; do
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
  kubectl get nodes -l "oke-llm/allocation=$platform" -o json > gpu-nodes.json
  kubectl get nodes -o json > cpu-nodes.json
  jq -n --slurpfile c config.json --slurpfile gpu gpu-nodes.json --slurpfile cpu cpu-nodes.json '{config:$c[0],gpu_nodes:$gpu[0],cpu_nodes:$cpu[0]}' | jq -f readiness.jq > node-readiness.json
  if jq -e .ready node-readiness.json >/dev/null; then ready=true; break; fi
  if jq -e .fatal node-readiness.json >/dev/null; then break; fi
  sleep 10
done
[[ "$ready" == true ]] || { jq -r '.reasons[]' node-readiness.json >&2; exit 1; }
if [[ $(jq -r .enable_lws config.json) == true ]]; then
  release=$(jq -er .components.lws.release config.json)
  namespace=$(jq -er .components.lws.namespace config.json)
  version=$(jq -er .components.lws.version config.json)
  helm list --all --all-namespaces -o json > helm-releases.json
  kubectl get crd leaderworkersets.leaderworkerset.x-k8s.io --ignore-not-found -o json > existing-crd.json
  existing=$(jq --arg release "$release" --arg namespace "$namespace" '[.[]|select(.name==$release and .namespace==$namespace)]|length' helm-releases.json)
  if [[ -s existing-crd.json || "$existing" != 0 ]]; then
    if [[ -s existing-crd.json ]]; then
      # Helm's crds/ installer does not add release ownership annotations. In
      # that case reuse only an unambiguous existing LWS release, without edits.
      owner=$(jq -r '.metadata.annotations["meta.helm.sh/release-name"] // empty' existing-crd.json)
      if [[ -n "$owner" ]]; then
        release=$owner
        namespace=$(jq -er '.metadata.annotations["meta.helm.sh/release-namespace"]' existing-crd.json)
      else
        jq -e '[.[]|select(.chart|startswith("lws-"))] | if length==1 then .[0] else error("LWS CRD exists without one identifiable Helm controller release; review ownership before bootstrap") end' helm-releases.json > existing-release.json
        release=$(jq -er .name existing-release.json)
        namespace=$(jq -er .namespace existing-release.json)
      fi
    fi
    jq -e --arg release "$release" --arg namespace "$namespace" --arg chart "lws-$version" 'any(.[]; .name==$release and .namespace==$namespace and .chart==$chart and .status=="deployed")' helm-releases.json >/dev/null || {
      echo 'Existing LWS installation is not the expected healthy chart version. Review its ownership/version; no adoption or upgrade was attempted.' >&2; exit 1;
    }
    action=reused
  else
    affinity=$(jq -c --slurpfile nodes cpu-nodes.json '{nodeAffinity:{requiredDuringSchedulingIgnoredDuringExecution:{nodeSelectorTerms:[{matchExpressions:[{key:"node.kubernetes.io/instance-type",operator:"Exists"},{key:"node.kubernetes.io/instance-type",operator:"NotIn",values:((.gpu_shapes + [$nodes[0].items[].metadata.labels["node.kubernetes.io/instance-type"] // "" | select(contains("GPU"))])|unique)}]}]}}}' config.json)
    helm upgrade --install "$release" "$(jq -er .components.lws.chart config.json)" --version "$version" --namespace "$namespace" --create-namespace --set-json "affinity=$affinity" --wait --timeout 10m
    action=installed
  fi
  kubectl wait --for=condition=Established crd/leaderworkersets.leaderworkerset.x-k8s.io --timeout=60s
  kubectl get deployments -n "$namespace" -l "app.kubernetes.io/instance=$release" -o json > lws-deployments.json
  jq -e '.items|length>0' lws-deployments.json >/dev/null
  jq -r '.items[].metadata.name' lws-deployments.json > deployment-names.txt
  while IFS= read -r deployment; do kubectl rollout status "deployment/$deployment" -n "$namespace" --timeout=5m; done < deployment-names.txt
  # A server-side dry run checks API/webhook admission without persisting an
  # instance or scheduling any pods. The probe image is never pulled.
  jq -n --arg name "$platform-bootstrap-probe" --arg namespace "$namespace" '{apiVersion:"leaderworkerset.x-k8s.io/v1",kind:"LeaderWorkerSet",metadata:{name:$name,namespace:$namespace},spec:{replicas:0,leaderWorkerTemplate:{size:1,workerTemplate:{spec:{containers:[{name:"probe",image:"registry.k8s.io/pause:3.10"}]}}}}}' | kubectl apply --dry-run=server -f - -o json > lws-admission.json
  jq -n --arg action "$action" --arg release "$release" --arg namespace "$namespace" --arg version "$version" '{lws:{action:$action,release:$release,namespace:$namespace,chart_version:$version,admission:"server_dry_run_passed"}}' > controllers.json
fi
