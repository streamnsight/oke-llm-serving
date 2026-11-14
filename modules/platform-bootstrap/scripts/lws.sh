#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Component operations, sourced by the shared environment/tool/evidence runner.
if [[ $(jq -r .enable_lws config.json) != true ]]; then return; fi
release=$LWS_RELEASE
namespace=$LWS_NAMESPACE
version=$LWS_VERSION
helm list --all --all-namespaces -o json > helm-releases.json
kubectl get crd leaderworkersets.leaderworkerset.x-k8s.io --ignore-not-found -o json > existing-crd.json
existing=$(jq --arg release "$release" --arg namespace "$namespace" '[.[]|select(.name==$release and .namespace==$namespace)]|length' helm-releases.json)
affinity=$(jq -c '{nodeAffinity:{requiredDuringSchedulingIgnoredDuringExecution:{nodeSelectorTerms:[{matchExpressions:([{key:"node.kubernetes.io/instance-type",operator:"In",values:.cpu_shapes}]+["nvidia.com/gpu","nvidia.com/gpu.present","oci.oraclecloud.com/gpu-shape","feature.node.kubernetes.io/pci-10de.present"]|map(if type=="string" then {key:.,operator:"NotIn",values:["true"]} else . end))}]}}}' node-readiness.json)
if [[ -s existing-crd.json || "$existing" != 0 ]]; then
  if [[ -s existing-crd.json ]]; then
    # Helm's crds/ installer normally leaves ownership annotations unset.
    owner=$(jq -r '.metadata.annotations["meta.helm.sh/release-name"] // empty' existing-crd.json)
    if [[ -n "$owner" ]]; then
      release=$owner
      namespace=$(jq -er '.metadata.annotations["meta.helm.sh/release-namespace"]' existing-crd.json)
    else
      jq -e '[.[]|select(.chart|startswith("lws-"))] | if length==1 then .[0] else error("LWS CRD exists without one identifiable Helm controller release; review ownership before deployment") end' helm-releases.json > existing-release.json
      release=$(jq -er .name existing-release.json)
      namespace=$(jq -er .namespace existing-release.json)
    fi
  fi
  jq -e --arg release "$release" --arg namespace "$namespace" 'any(.[]; .name==$release and .namespace==$namespace and (.chart|startswith("lws-")) and .status=="deployed")' helm-releases.json >/dev/null || {
    echo 'Existing LWS release is not identifiable and healthy; no adoption or upgrade was attempted.' >&2; exit 1;
  }
  action=reused
  if [[ "$PLATFORM_MODE" == deploy && "$LWS_OPERATION" == upgrade ]]; then
    [[ "$release" == "$LWS_RELEASE" && "$namespace" == "$LWS_NAMESPACE" ]] || {
      echo 'Upgrade must explicitly target the configured existing release and namespace; refusing to change another owner.' >&2; exit 1;
    }
    # Helm does not upgrade files in crds/. Respect field ownership; never force
    # conflicts or delete CRDs (which could delete running model resources).
    helm show crds "$LWS_CHART" --version "$version" > lws-crds.yaml
    [[ -s lws-crds.yaml ]] || { echo 'The selected LWS chart has no CRDs.' >&2; exit 1; }
    kubectl apply --server-side --field-manager=oke-llm-lws -f lws-crds.yaml
    helm upgrade "$release" "$LWS_CHART" --version "$version" --namespace "$namespace" --reuse-values --set-json "affinity=$affinity" --wait --timeout 10m
    action=upgraded
  else
    jq -e --arg release "$release" --arg namespace "$namespace" --arg version "${version#v}" 'any(.[]; .name==$release and .namespace==$namespace and (.chart==("lws-"+$version) or .chart==("lws-v"+$version)))' helm-releases.json >/dev/null || {
      echo 'Existing LWS installation differs from the requested chart version; no adoption or upgrade was attempted. Use the LWS pipeline with LWS_OPERATION=upgrade and the correct owner to update explicitly.' >&2; exit 1;
    }
  fi
else
  [[ "$PLATFORM_MODE" == deploy ]] || { echo 'LWS is not installed; run the LWS deployment pipeline first.' >&2; exit 1; }
  helm upgrade --install "$release" "$LWS_CHART" --version "$version" --namespace "$namespace" --create-namespace --set-json "affinity=$affinity" --wait --timeout 10m
  action=installed
fi
kubectl wait --for=condition=Established crd/leaderworkersets.leaderworkerset.x-k8s.io --timeout=60s
kubectl get deployments -n "$namespace" -l "app.kubernetes.io/instance=$release" -o json > lws-deployments.json
jq -e '.items|length>0' lws-deployments.json >/dev/null
jq -r '.items[].metadata.name' lws-deployments.json > deployment-names.txt
while IFS= read -r deployment; do kubectl rollout status "deployment/$deployment" -n "$namespace" --timeout=5m; done < deployment-names.txt
# The admission probe persists no instance and schedules no pods.
jq -n --arg name "$platform-bootstrap-probe" --arg namespace "$namespace" '{apiVersion:"leaderworkerset.x-k8s.io/v1",kind:"LeaderWorkerSet",metadata:{name:$name,namespace:$namespace},spec:{replicas:0,leaderWorkerTemplate:{size:1,workerTemplate:{spec:{containers:[{name:"probe",image:"registry.k8s.io/pause:3.10"}]}}}}}' | kubectl apply --dry-run=server -f - -o json > lws-admission.json
jq -n --arg action "$action" --arg release "$release" --arg namespace "$namespace" --arg version "$version" '{lws:{action:$action,release:$release,namespace:$namespace,chart_version:$version,admission:"server_dry_run_passed"}}' > controllers.json
