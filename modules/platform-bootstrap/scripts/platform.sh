#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Coordinate independent components; never alter GPU allocations or model data.
set -euo pipefail
for tool in jq curl tar sha256sum oci; do command -v "$tool" >/dev/null; done
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
spec=$(realpath "$script_dir/platform.json")
: "${PLATFORM_MODE:?}" "${REGION:?}" "${CLUSTER_ID:?}" "${PLATFORM_NAME:?}" "${RESULT_REPOSITORY_ID:?}"
[[ "$PLATFORM_MODE" == deploy || "$PLATFORM_MODE" == validate ]]
[[ "$REGION" == "$(jq -r .region "$spec")" && "$CLUSTER_ID" == "$(jq -r .cluster_id "$spec")" && "$PLATFORM_NAME" == "$(jq -r .platform_name "$spec")" ]] || {
  echo 'Platform binding overrides require a newly reviewed stack specification.' >&2; exit 2;
}
export OCI_CLI_AUTH=resource_principal OCI_CLI_REGION="$REGION"
run_dir=$(mktemp -d)
trap 'rm -rf "$run_dir"' EXIT
cd "$run_dir"
cp "$spec" config.json
# UUID also works when a Shell runtime omits OCI_DEPLOYMENT_ID. No shared key.
execution=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
generation=$(jq -er .generation config.json)
report_path="$PLATFORM_NAME/platform/$generation/$PLATFORM_MODE/$execution"
printf '{}\n' > components.json
printf '{}\n' > node-readiness.json
archive() {
  local result=$?
  trap - EXIT
  jq -n --arg execution "$execution" --arg deployment_id "${OCI_DEPLOYMENT_ID:-}" --arg mode "$PLATFORM_MODE" --arg generation "$generation" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson exit_code "$result" --slurpfile nodes node-readiness.json --slurpfile components components.json \
    '{generation:$generation,execution:$execution,deployment_id:$deployment_id,mode:$mode,checked_at:$at,status:(if $exit_code==0 then "ready" else "failed" end),exit_code:$exit_code,node_checks:$nodes[0],components:$components[0],model_runtime_validation:"not_run",gpu_fabric_validation:"not_run"}' > report.json
  if ! oci artifacts generic artifact upload-by-path --repository-id "$RESULT_REPOSITORY_ID" --artifact-path "$report_path/report.json" --artifact-version "$execution" --content-body report.json >/dev/null; then result=1; fi
  echo "Platform result: repository=$RESULT_REPOSITORY_ID path=$report_path/report.json version=$execution"
  rm -rf "$run_dir"
  exit "$result"
}
trap archive EXIT
if [[ "$PLATFORM_MODE" == deploy ]]; then
  jq -c '[.components|to_entries[]|select(.value.mode!="retire")|.key]' config.json > pending.json
  printf '[]\n' > complete.json
  while [[ $(jq length pending.json) -gt 0 ]]; do
    jq -n --slurpfile c config.json --slurpfile pending pending.json --slurpfile complete complete.json \
      '[$pending[0][] as $k|select(all($c[0].components[$k].dependency_keys[]; . as $d|$complete[0]|index($d)!=null))|$k]' > wave.json
    [[ $(jq length wave.json) -gt 0 ]] || { echo 'Component dependency cycle or missing prerequisite.' >&2; exit 1; }
    pids=()
    while IFS= read -r component; do
      (
        pipeline=$(jq -er --arg k "$component" '.components[$k].pipeline_id' config.json)
        child=$(oci devops deployment create-pipeline-deployment --pipeline-id "$pipeline" --display-name "${PLATFORM_NAME}-${component}-${execution:0:8}" --query data.id --raw-output)
        [[ "$child" == ocid1.devopsdeployment.* ]] || exit 1
        echo "Started $component: $child"
        state=IN_PROGRESS
        for attempt in $(seq 1 200); do
          state=$(oci devops deployment get --deployment-id "$child" --query 'data."lifecycle-state"' --raw-output)
          case "$state" in SUCCEEDED) break;; FAILED|CANCELED|CANCELLED) echo "$component deployment $state: $child" >&2; exit 1;; esac
          sleep 15
        done
        [[ "$state" == SUCCEEDED ]] || { echo "$component timed out; child $child may still run. Inspect it before retrying." >&2; exit 1; }
        jq -n --arg pipeline_id "$pipeline" --arg deployment_id "$child" '{pipeline_id:$pipeline_id,deployment_id:$deployment_id,status:"SUCCEEDED"}' > "child-$component.json"
      ) &
      pids+=("$!")
    done < <(jq -r '.[]' wave.json)
    failed=0
    for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
    [[ "$failed" == 0 ]] || exit 1
    jq -n --slurpfile complete complete.json --slurpfile wave wave.json '$complete[0]+$wave[0]' > next.json; mv next.json complete.json
    jq -n --slurpfile pending pending.json --slurpfile wave wave.json '$pending[0]-$wave[0]' > next.json; mv next.json pending.json
  done
fi
mkdir bin
export PATH="$PWD/bin:$PATH"
kube_version=$(jq -er .target.kubernetes_version config.json)
helm_version=$(jq -er .helm_version config.json)
[[ "$kube_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ && "$helm_version" =~ ^v3\.[0-9]+\.[0-9]+$ ]]
curl -fsSL --retry 3 "https://dl.k8s.io/release/$kube_version/bin/linux/amd64/kubectl" -o bin/kubectl
curl -fsSL --retry 3 "https://dl.k8s.io/release/$kube_version/bin/linux/amd64/kubectl.sha256" -o kubectl.sha256
printf '%s  bin/kubectl\n' "$(cat kubectl.sha256)" | sha256sum -c -
curl -fsSL --retry 3 "https://get.helm.sh/helm-$helm_version-linux-amd64.tar.gz" -o helm.tgz
curl -fsSL --retry 3 "https://get.helm.sh/helm-$helm_version-linux-amd64.tar.gz.sha256sum" -o helm.sha256
printf '%s  helm.tgz\n' "$(cut -d ' ' -f 1 helm.sha256)" | sha256sum -c -
tar -xzf helm.tgz linux-amd64/helm
mv linux-amd64/helm bin/helm
chmod +x bin/helm bin/kubectl
export KUBECONFIG="$PWD/kubeconfig"
oci ce cluster create-kubeconfig --cluster-id "$CLUSTER_ID" --file "$KUBECONFIG" --region "$REGION" --token-version 2.0.0 --kube-endpoint PRIVATE_ENDPOINT >/dev/null
if jq -e '.gpu_allocation_enabled!=false' config.json >/dev/null; then kubectl get nodes -l "oke-llm/allocation=$PLATFORM_NAME" -o json > gpu-nodes.json; else printf '{"items":[]}\n' > gpu-nodes.json; fi
kubectl get nodes -o json > cpu-nodes.json
jq -n --slurpfile c config.json --slurpfile gpu gpu-nodes.json --slurpfile cpu cpu-nodes.json '{config:$c[0],gpu_nodes:$gpu[0],cpu_nodes:$cpu[0]}' | jq -f "$script_dir/readiness.jq" > node-readiness.json
jq -e .ready node-readiness.json >/dev/null || { jq -r '.reasons[]' node-readiness.json >&2; exit 1; }
while IFS= read -r component; do
  namespace=$(jq -r --arg k "$component" '.components[$k].namespace' config.json)
  release=$(jq -r --arg k "$component" '.components[$k].release_name' config.json)
  helm status "$release" --namespace "$namespace" -o json > "helm-$component.json"
  jq -e '.info.status=="deployed"' "helm-$component.json" >/dev/null
  if [[ $(jq -r --arg k "$component" '.components[$k].mode' config.json) == managed ]]; then
    owner_name=$(jq -er --arg k "$component" '.components[$k].owner_name' config.json)
    kubectl get configmap "$owner_name" -n "$namespace" -o json > "owner-$component.json"
    jq -e --slurpfile c config.json --arg k "$component" '.data.generation==$c[0].components[$k].generation and .data.status=="ready" and .data.ownership_token==$c[0].components[$k].ownership_token' "owner-$component.json" >/dev/null
    jq -e --slurpfile h "helm-$component.json" '.data.helm_revision==($h[0].version|tostring) and (.data.chart_version|ltrimstr("v"))==($h[0].chart.metadata.version|ltrimstr("v"))' "owner-$component.json" >/dev/null || { echo 'Helm release drifted after its last validated component run.' >&2; exit 1; }
    last_deployment=$(jq -er .data.deployment_id "owner-$component.json")
    [[ $(oci devops deployment get --deployment-id "$last_deployment" --query 'data."lifecycle-state"' --raw-output) == SUCCEEDED ]] || { echo 'Component evidence refers to an incomplete deployment.' >&2; exit 1; }
  fi
  while IFS= read -r crd; do kubectl wait --for=condition=Established --timeout=120s "crd/$crd"; done < <(jq -r --arg k "$component" '.components[$k].crd_names[]' config.json)
  while IFS= read -r deployment; do kubectl rollout status "deployment/$deployment" -n "$namespace" --timeout=120s; done < <(jq -r --arg k "$component" '.components[$k].deployment_names[]' config.json)
  jq --arg k "$component" --slurpfile h "helm-$component.json" --slurpfile c config.json '.+{($k):{generation:$c[0].components[$k].generation,mode:$c[0].components[$k].mode,release:$h[0].name,namespace:$h[0].namespace,revision:$h[0].version,chart_version:$h[0].chart.metadata.version,status:$h[0].info.status}}' components.json > next.json
  mv next.json components.json
  # Monitoring also needs its actual Prometheus workload, not only the operator.
  if [[ "$component" == prometheus ]]; then
    kubectl rollout status statefulset/prometheus-llm-monitoring-kube-prom-prometheus -n "$namespace" --timeout=120s
    kubectl get pvc -n "$namespace" -l operator.prometheus.io/name=llm-monitoring-kube-prom-prometheus -o json > prometheus-pvcs.json
    jq -e '.items|length>0 and all(.[];.status.phase=="Bound")' prometheus-pvcs.json >/dev/null
  elif [[ "$component" == keda ]]; then
    kubectl wait --for=condition=Available --timeout=120s apiservice/v1beta1.external.metrics.k8s.io
  fi
done < <(jq -r '.components|to_entries[]|select(.value.mode!="retire")|.key' config.json)
