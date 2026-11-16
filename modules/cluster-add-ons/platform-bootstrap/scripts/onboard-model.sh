#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Trusted platform operation, never a model-principal self-authorization path.
set -euo pipefail
for tool in jq curl sha256sum oci; do command -v "$tool" >/dev/null || { echo "Missing onboarding tool: $tool" >&2; exit 2; }; done
[[ "$PLATFORM_NAME" =~ ^[a-z][a-z0-9-]{0,30}[a-z0-9]$ && "$MODEL_NAMESPACE" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ && "$MODEL_NAMESPACE" == "$PLATFORM_NAME-model-"* ]] || { echo 'Model namespace must be a DNS label beginning <platform>-model-' >&2; exit 2; }
[[ ${MODEL_PROJECT_ID:-} =~ ^ocid1\.devopsproject\.[A-Za-z0-9._-]+$ ]] || { echo 'MODEL_PROJECT_ID must identify the explicitly selected independent model project' >&2; exit 2; }
[[ ${MODEL_GPU_POOL_ID:-runtime} == runtime || ${MODEL_GPU_POOL_ID:-} =~ ^ocid1\.nodepool\.[A-Za-z0-9._-]+$ ]] || { echo 'MODEL_GPU_POOL_ID must be runtime or an exact OKE pool OCID' >&2; exit 2; }
MODEL_GPU_POOL_ID=${MODEL_GPU_POOL_ID:-runtime}
[[ "$MODEL_ACCESS_OPERATION" == grant || "$MODEL_ACCESS_OPERATION" == revoke ]] || { echo 'MODEL_ACCESS_OPERATION must be grant or revoke' >&2; exit 2; }
MODEL_PIPELINE_IDS=$(jq -cn --arg ids "${MODEL_PIPELINE_IDS:-}" '$ids | split(",")')
jq -e 'type=="array" and length>0 and length<=16 and (unique|length)==length and all(.[];type=="string" and test("^ocid1\\.devopsdeploypipeline\\.[A-Za-z0-9._-]+$"))' <<< "$MODEL_PIPELINE_IDS" >/dev/null || {
  echo 'MODEL_PIPELINE_IDS must contain 1 to 16 unique exact deployment pipeline OCIDs separated by commas, with no empty entries or whitespace' >&2
  exit 2
}
export MODEL_PIPELINE_IDS
[[ "$KUBERNETES_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
jq -e '.components|type=="object" and all(to_entries[];
  (.key|test("^[a-z0-9-]+$")) and (.value.namespace|test("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$")) and
  (.value.mode|.=="managed" or .=="reuse" or .=="retire") and
  (.value.owner_name|test("^[a-z0-9][a-z0-9.-]*$")) and
  (.value.ownership_token|test("^[a-f0-9]{64}$")) and (.value.release_name|test("^[a-z0-9][a-z0-9.-]*$")) and
  (.value.crd_names|type=="array" and all(.[];test("^[a-z0-9][a-z0-9.-]*$"))) and
  (.value.deployment_names|type=="array" and all(.[];test("^[a-z0-9][a-z0-9.-]*$"))))' "$script_dir/model-access-context.json" >/dev/null
work_dir=$(mktemp -d)
execution=$(cat /proc/sys/kernel/random/uuid)
namespace_hash=$(printf '%s' "$MODEL_NAMESPACE" | sha256sum | cut -c1-12)
reader_name="oke-llm-model-reader-$namespace_hash"
owner=$(printf '%s' "$PLATFORM_NAME/$CLUSTER_ID" | sha256sum | cut -c1-32)
locked=false
export OCI_CLI_AUTH=resource_principal OCI_CLI_REGION
finish() {
  local code=$?
  trap - EXIT
  if [[ "$locked" == true ]]; then
    if kubectl get lease oke-llm-model-onboarding -n "$MODEL_NAMESPACE" -o json > "$work_dir/lease.json" && jq -e --arg holder "$execution" '.spec.holderIdentity==$holder' "$work_dir/lease.json" >/dev/null; then
      kubectl delete lease oke-llm-model-onboarding -n "$MODEL_NAMESPACE" --wait=true >/dev/null || { (( code != 0 )) || code=1; }
    else (( code != 0 )) || code=1; fi
  fi
  jq -n --arg execution "$execution" --arg namespace "$MODEL_NAMESPACE" --arg project "$MODEL_PROJECT_ID" --arg action "$MODEL_ACCESS_OPERATION" --arg owner "$owner" --argjson ids "$MODEL_PIPELINE_IDS" --argjson exit_code "$code" \
    '{operation:"model_access",action:$action,namespace:$namespace,project_id:$project,platform_owner:$owner,pipeline_ids:$ids,execution_id:$execution,status:(if $exit_code==0 then "passed" else "failed" end),exit_code:$exit_code,model_runtime_validation:"not_run"}' || { (( code != 0 )) || code=1; }
  rm -rf "$work_dir" || { (( code != 0 )) || code=1; }
  exit "$code"
}
trap finish EXIT
# Project separation is intentional. The trusted platform operator explicitly names
# the model project; every exact principal must declare the same target boundary.
if [[ "$MODEL_ACCESS_OPERATION" == grant ]]; then
  oci devops project get --project-id "$MODEL_PROJECT_ID" > "$work_dir/project.json" || { echo 'Trusted onboarding cannot read this model project. Verify the OCID and grant the trusted platform identity read devops-family in the model project compartment when it differs from the platform compartment; no tenancy-wide grant is added automatically' >&2; exit 1; }
  jq -e --arg id "$MODEL_PROJECT_ID" '.data.id==$id and .data["lifecycle-state"]=="ACTIVE"' "$work_dir/project.json" >/dev/null || { echo 'Model project is missing or not active' >&2; exit 1; }
  while IFS= read -r pipeline; do
    oci devops deploy-pipeline get --pipeline-id "$pipeline" > "$work_dir/pipeline.json" || { echo 'Trusted onboarding cannot read this exact model pipeline. Verify its OCID and the platform identity read permission in the model project compartment' >&2; exit 1; }
    jq -e --arg project "$MODEL_PROJECT_ID" --arg id "$pipeline" --arg namespace "$MODEL_NAMESPACE" --arg cluster "$CLUSTER_ID" --arg platform "$PLATFORM_NAME" --arg pool "$MODEL_GPU_POOL_ID" '
      .data as $p | ($p["deploy-pipeline-parameters"].items // []) as $items |
      ($items|map({key:.name,value:.["default-value"]})|from_entries) as $args |
      ($items|map(.name)|unique|length)==($items|length) and
      $p.id==$id and $p["project-id"]==$project and $p["lifecycle-state"]=="ACTIVE" and
      $args.MODEL_NAMESPACE==$namespace and $args.MODEL_PROJECT_ID==$project and
      $args.MODEL_CLUSTER_ID==$cluster and $args.MODEL_PLATFORM_NAME==$platform and $args.MODEL_GPU_POOL_ID==$pool
    ' "$work_dir/pipeline.json" >/dev/null || { echo 'Pipeline must be active in the selected model project and declare this exact model project/cluster/platform/pool/namespace boundary' >&2; exit 1; }
  done < <(jq -r '.[]' <<< "$MODEL_PIPELINE_IDS")
fi
# Revoke deliberately uses the persisted owned bindings: even deleted pipelines
# must remain removable without needing their former metadata to be active.
mkdir "$work_dir/bin"
export PATH="$work_dir/bin:$PATH"
curl -fsSL --retry 3 "https://dl.k8s.io/release/$KUBERNETES_VERSION/bin/linux/amd64/kubectl" -o "$work_dir/bin/kubectl"
curl -fsSL --retry 3 "https://dl.k8s.io/release/$KUBERNETES_VERSION/bin/linux/amd64/kubectl.sha256" -o "$work_dir/kubectl.sha256"
printf '%s  %s\n' "$(cat "$work_dir/kubectl.sha256")" "$work_dir/bin/kubectl" | sha256sum -c -
chmod +x "$work_dir/bin/kubectl"
oci ce cluster create-kubeconfig --cluster-id "$CLUSTER_ID" --file "$work_dir/kubeconfig" --region "$OCI_CLI_REGION" --token-version 2.0.0 --kube-endpoint PRIVATE_ENDPOINT >/dev/null
export KUBECONFIG=$work_dir/kubeconfig
jq -n --arg owner "$owner" --arg namespace "$MODEL_NAMESPACE" --arg platform "$PLATFORM_NAME" --arg cluster "$CLUSTER_ID" --arg project "$MODEL_PROJECT_ID" --arg reader "$reader_name" -f "$script_dir/model-access.jq" > "$work_dir/access.json"
check_owner() {
  jq -e --arg owner "$owner" --arg namespace "$MODEL_NAMESPACE" --arg platform "$PLATFORM_NAME" --arg cluster "$CLUSTER_ID" --arg project "$MODEL_PROJECT_ID" '
    .metadata.labels["oke-llm/platform-owner"]==$owner and .metadata.annotations["oke-llm/model-namespace"]==$namespace and
    .metadata.annotations["oke-llm/platform-name"]==$platform and .metadata.annotations["oke-llm/cluster-id"]==$cluster and .metadata.annotations["oke-llm/model-project-id"]==$project' "$1" >/dev/null
}
kubectl get namespace "$MODEL_NAMESPACE" --ignore-not-found -o json > "$work_dir/existing.json"
if [[ -s "$work_dir/existing.json" ]]; then
  check_owner "$work_dir/existing.json" && jq -e '.metadata.labels["oke-llm/model-namespace"]=="true"' "$work_dir/existing.json" >/dev/null || { echo 'Refusing an existing namespace with foreign/missing model-platform ownership' >&2; exit 1; }
else
  [[ "$MODEL_ACCESS_OPERATION" == grant ]] || { echo 'Namespace does not exist; nothing to revoke' >&2; exit 1; }
  jq .namespace "$work_dir/access.json" > "$work_dir/namespace.json"
  kubectl create -f "$work_dir/namespace.json" >/dev/null
fi
jq -n --arg ns "$MODEL_NAMESPACE" --arg holder "$execution" '{apiVersion:"coordination.k8s.io/v1",kind:"Lease",metadata:{name:"oke-llm-model-onboarding",namespace:$ns},spec:{holderIdentity:$holder,leaseDurationSeconds:2100}}' > "$work_dir/lease-create.json"
kubectl create -f "$work_dir/lease-create.json" >/dev/null || { echo 'Onboarding already locked; inspect the previous execution before recovering an orphaned lease' >&2; exit 1; }
locked=true
apply_owned() {
  local kind=$1 name=$2 file=$3 scope=$4
  local target_namespace=$MODEL_NAMESPACE
  [[ "$scope" != namespace:* ]] || target_namespace=${scope#namespace:}
  if [[ "$scope" == cluster ]]; then kubectl get "$kind" "$name" --ignore-not-found -o json > "$work_dir/existing.json"
  else kubectl get "$kind" "$name" -n "$target_namespace" --ignore-not-found -o json > "$work_dir/existing.json"; fi
  if [[ -s "$work_dir/existing.json" ]]; then
    check_owner "$work_dir/existing.json" || { echo "Refusing foreign RBAC: $kind/$name" >&2; return 1; }
    jq --slurpfile old "$work_dir/existing.json" '.metadata.resourceVersion=$old[0].metadata.resourceVersion' "$file" > "$work_dir/replace.json"
    kubectl replace -f "$work_dir/replace.json" >/dev/null
  else kubectl create -f "$file" >/dev/null; fi
}
if [[ "$MODEL_ACCESS_OPERATION" == grant ]]; then
  jq .role "$work_dir/access.json" > "$work_dir/role.json"
  jq .reader "$work_dir/access.json" > "$work_dir/reader.json"
  apply_owned role oke-llm-model "$work_dir/role.json" namespace
  apply_owned clusterrole "$reader_name" "$work_dir/reader.json" cluster
  context_name="oke-llm-model-context-$(printf '%s' "$MODEL_NAMESPACE" | sha256sum | cut -c1-12)"
  jq --arg name "$context_name" --arg pool "$MODEL_GPU_POOL_ID" --slurpfile context "$script_dir/model-access-context.json" '
    .namespace | .kind="ConfigMap" | .metadata.name=$name | .metadata.namespace="kube-system" |
    .data={"context.json":({schema_version:"1.0",platform_name:.metadata.annotations["oke-llm/platform-name"],cluster_id:.metadata.annotations["oke-llm/cluster-id"],model_project_id:.metadata.annotations["oke-llm/model-project-id"],model_namespace:.metadata.annotations["oke-llm/model-namespace"],gpu_pool_id:$pool,components:$context[0].components}|tojson)}
  ' "$work_dir/access.json" > "$work_dir/runtime-context.json"
  apply_owned configmap "$context_name" "$work_dir/runtime-context.json" namespace:kube-system
  jq --arg name "$context_name-reader" --arg context "$context_name" '.role | .metadata.name=$name | .metadata.namespace="kube-system" | .rules=[{apiGroups:[""],resources:["configmaps"],resourceNames:[$context],verbs:["get"]}]' "$work_dir/access.json" > "$work_dir/context-reader.json"
  apply_owned role "$context_name-reader" "$work_dir/context-reader.json" namespace:kube-system
  for component in router_account router_role router_binding; do
    jq --arg component "$component" '.[$component]' "$work_dir/access.json" > "$work_dir/router.json"
    apply_owned "$(jq -r .kind "$work_dir/router.json")" "$(jq -r .metadata.name "$work_dir/router.json")" "$work_dir/router.json" namespace
  done
else
  kubectl get pods -n "$MODEL_NAMESPACE" -o json > "$work_dir/pods.json"
  jq -e 'all(.items[]; .status.phase=="Succeeded" or .status.phase=="Failed")' "$work_dir/pods.json" >/dev/null || { echo 'Retire/drain model workloads before revoking pipeline access' >&2; exit 1; }
fi
while IFS= read -r pipeline; do
  suffix=$(printf '%s' "$pipeline" | sha256sum | cut -c1-20)
  for kind in RoleBinding ClusterRoleBinding; do
    if [[ "$kind" == RoleBinding ]]; then scope=namespace; name=model-$suffix; else scope=cluster; name=model-$namespace_hash-$suffix-reader; fi
    jq --arg kind "$kind" --arg name "$name" --arg ns "$MODEL_NAMESPACE" --arg pipeline "$pipeline" --arg reader "$reader_name" '
      {apiVersion:"rbac.authorization.k8s.io/v1",kind:$kind,metadata:(.role.metadata|.name=$name|.annotations["oke-llm/pipeline-id"]=$pipeline),roleRef:{apiGroup:"rbac.authorization.k8s.io",kind:(if $kind=="RoleBinding" then "Role" else "ClusterRole" end),name:(if $kind=="RoleBinding" then "oke-llm-model" else $reader end)},subjects:[{kind:"User",name:$pipeline,apiGroup:"rbac.authorization.k8s.io"}]}
      | if $kind=="ClusterRoleBinding" then del(.metadata.namespace) else . end' "$work_dir/access.json" > "$work_dir/binding.json"
    if [[ "$MODEL_ACCESS_OPERATION" == grant ]]; then apply_owned "$kind" "$name" "$work_dir/binding.json" "$scope"
    else
      if [[ "$scope" == cluster ]]; then kubectl get "$kind" "$name" --ignore-not-found -o json > "$work_dir/existing.json"
      else kubectl get "$kind" "$name" -n "$MODEL_NAMESPACE" --ignore-not-found -o json > "$work_dir/existing.json"; fi
      if [[ -s "$work_dir/existing.json" ]]; then
        check_owner "$work_dir/existing.json" && jq -e --arg pipeline "$pipeline" '.metadata.annotations["oke-llm/pipeline-id"]==$pipeline' "$work_dir/existing.json" >/dev/null || exit 1
        if [[ "$scope" == cluster ]]; then kubectl delete "$kind" "$name" --wait=true >/dev/null
        else kubectl delete "$kind" "$name" -n "$MODEL_NAMESPACE" --wait=true >/dev/null; fi
      fi
    fi
  done
done < <(jq -r '.[]' <<< "$MODEL_PIPELINE_IDS")
if [[ "$MODEL_ACCESS_OPERATION" == grant ]]; then
  while IFS= read -r pipeline; do
    suffix=$(printf '%s' "$pipeline" | sha256sum | cut -c1-20)
    context_name="oke-llm-model-context-$(printf '%s' "$MODEL_NAMESPACE" | sha256sum | cut -c1-12)"
    jq --arg name "$context_name-$suffix" --arg role "$context_name-reader" --arg pipeline "$pipeline" '.role | {apiVersion,kind:"RoleBinding",metadata:(.metadata|.name=$name|.namespace="kube-system"|.annotations["oke-llm/pipeline-id"]=$pipeline),roleRef:{apiGroup:"rbac.authorization.k8s.io",kind:"Role",name:$role},subjects:[{kind:"User",name:$pipeline,apiGroup:"rbac.authorization.k8s.io"}]}' "$work_dir/access.json" > "$work_dir/context-binding.json"
    apply_owned rolebinding "$context_name-$suffix" "$work_dir/context-binding.json" namespace:kube-system
  done < <(jq -r '.[]' <<< "$MODEL_PIPELINE_IDS")
  namespace_hash=$(printf '%s' "$MODEL_NAMESPACE" | sha256sum | cut -c1-12)
  while IFS= read -r component; do
    component_namespace=$(jq -er --arg key "$component" '.components[$key].namespace' "$script_dir/model-access-context.json")
    role_name=model-$namespace_hash-$component-reader
    jq --arg name "$role_name" --arg ns "$component_namespace" --arg key "$component" --slurpfile context "$script_dir/model-access-context.json" '
      $context[0].components[$key] as $c | .role | .metadata.name=$name | .metadata.namespace=$ns |
      .rules=([{apiGroups:["apps"],resources:["deployments"],resourceNames:$c.deployment_names,verbs:["get"]}] +
        if $c.mode=="managed" then [{apiGroups:[""],resources:["configmaps"],resourceNames:[$c.owner_name],verbs:["get"]}] else [] end)
    ' "$work_dir/access.json" > "$work_dir/component-reader.json"
    apply_owned role "$role_name" "$work_dir/component-reader.json" "namespace:$component_namespace"
    while IFS= read -r pipeline; do
      suffix=$(printf '%s' "$pipeline" | sha256sum | cut -c1-20)
      binding_name=model-$namespace_hash-$component-$suffix
      jq --arg name "$binding_name" --arg pipeline "$pipeline" '
        {apiVersion:"rbac.authorization.k8s.io/v1",kind:"RoleBinding",metadata:(.metadata|.name=$name|.annotations["oke-llm/pipeline-id"]=$pipeline),
         roleRef:{apiGroup:"rbac.authorization.k8s.io",kind:"Role",name:.metadata.name},subjects:[{kind:"User",name:$pipeline,apiGroup:"rbac.authorization.k8s.io"}]}
      ' "$work_dir/component-reader.json" > "$work_dir/component-binding.json"
      apply_owned rolebinding "$binding_name" "$work_dir/component-binding.json" "namespace:$component_namespace"
    done < <(jq -r '.[]' <<< "$MODEL_PIPELINE_IDS")
  done < <(jq -r '.components|to_entries[]|select(.value.mode!="retire")|.key' "$script_dir/model-access-context.json")
else
  # Removed components must not leave stale read bindings in former namespaces.
  kubectl get rolebindings --all-namespaces -l "oke-llm/platform-owner=$owner,oke-llm/model-access=$MODEL_NAMESPACE" -o json > "$work_dir/component-bindings.json"
  while IFS=$'\t' read -r binding_namespace binding_name pipeline; do
    kubectl get rolebinding "$binding_name" -n "$binding_namespace" -o json > "$work_dir/existing.json"
    check_owner "$work_dir/existing.json" && jq -e --arg pipeline "$pipeline" '.metadata.annotations["oke-llm/pipeline-id"]==$pipeline' "$work_dir/existing.json" >/dev/null || exit 1
    kubectl delete rolebinding "$binding_name" -n "$binding_namespace" --wait=true >/dev/null
  done < <(jq -r --argjson ids "$MODEL_PIPELINE_IDS" --arg namespace "$MODEL_NAMESPACE" --arg owner "$owner" '.items[]|select(.metadata.labels["oke-llm/platform-owner"]==$owner and .metadata.annotations["oke-llm/model-namespace"]==$namespace and (.metadata.annotations["oke-llm/pipeline-id"] as $id|$ids|index($id))!=null)|[.metadata.namespace,.metadata.name,.metadata.annotations["oke-llm/pipeline-id"]]|@tsv' "$work_dir/component-bindings.json")
fi
echo "Model pipeline access $MODEL_ACCESS_OPERATION complete: $MODEL_NAMESPACE"
