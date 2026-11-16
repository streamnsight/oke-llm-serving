#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# DevOps control script: only small config/scripts/reports touch the runner disk.
set +x
set -euo pipefail
for tool in curl jq sha256sum oci; do command -v "$tool" >/dev/null || { echo "Missing DevOps tool: $tool" >&2; exit 2; }; done
input_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
printf '%s  %s\n' "$MODEL_CONFIG_SHA256" "$input_dir/model.json" | sha256sum -c -
jq -e -f "$input_dir/validate.jq" "$input_dir/model.json" >/dev/null
[[ "$STAGING_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9./:_-]*@sha256:[a-f0-9]{64}$ ]] || { echo 'STAGING_IMAGE must be digest-pinned' >&2; exit 2; }
staging_repository=${STAGING_IMAGE%@*}
staging_first_part=${staging_repository%%/*}
if [[ $staging_repository != */* ]]; then
  STAGING_IMAGE="docker.io/library/$STAGING_IMAGE"
elif [[ $staging_first_part != *.* && $staging_first_part != *:* && $staging_first_part != localhost ]]; then
  STAGING_IMAGE="docker.io/$STAGING_IMAGE"
fi
export STAGING_IMAGE
[[ "$JOB_DEADLINE_SECONDS" =~ ^[1-9][0-9]{2,4}$ && "$JOB_DEADLINE_SECONDS" -ge 300 && "$JOB_DEADLINE_SECONDS" -le 25200 ]] || { echo 'Job deadline must be 300..25200 seconds' >&2; exit 2; }
[[ "$KUBERNETES_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ && "$MODEL_STAGE_NAME" =~ ^[a-z][a-z0-9-]{0,30}[a-z0-9]$ ]] || exit 2
run_dir=$(mktemp -d)
run_id=$(cat /proc/sys/kernel/random/uuid)
namespace=$(jq -er .namespace "$input_dir/model.json")
owner=$(jq -er .owner "$input_dir/model.json")
service_account=$(jq -er .service_account "$input_dir/model.json")
pvc=$(jq -er .pvc_name "$input_dir/model.json")
storage_class=$(jq -er .storage_class "$input_dir/model.json")
job=$MODEL_STAGE_NAME-download
configmap=stage-${run_id}
created_job=false
created_configmap=false
export OCI_CLI_AUTH=resource_principal OCI_CLI_REGION
finish() {
  local status=$? cleanup_status=0
  trap - EXIT
  if [[ "$created_job" == true ]]; then
    kubectl -n "$namespace" logs "job/$job" --all-containers=true || true
    kubectl -n "$namespace" get job "$job" -o json > "$run_dir/job-result.json" || true
    kubectl -n "$namespace" delete job "$job" --wait=true --timeout=120s || cleanup_status=1
  fi
  if [[ "$created_configmap" == true ]]; then kubectl -n "$namespace" delete configmap "$configmap" --ignore-not-found=true || cleanup_status=1; fi
  (( status != 0 )) || status=$cleanup_status
  if jq -n --arg run_id "$run_id" --arg checked_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg image "$STAGING_IMAGE" --argjson deadline "$JOB_DEADLINE_SECONDS" \
    --argjson exit_code "$status" --arg config_sha256 "$MODEL_CONFIG_SHA256" --slurpfile config "$input_dir/model.json" \
    '{schema_version:"1.0",operation:"stage_model_weights",run_id:$run_id,checked_at:$checked_at,status:(if $exit_code==0 then "staged" else "failed" end),exit_code:$exit_code,config_sha256:$config_sha256,snapshot_sha256:$config[0].snapshot_sha256,staging_image:$image,deadline_seconds:$deadline,bucket:$config[0].bucket,manifest_key:($config[0].prefix+"/manifest.json"),model_serving_validation:"not_run"}' > "$run_dir/report.json"; then
    echo 'Model staging report:' || cleanup_status=1
    cat "$run_dir/report.json" || cleanup_status=1
  else
    cleanup_status=1
  fi
  rm -rf "$run_dir" || cleanup_status=1
  (( status != 0 )) || status=$cleanup_status
  exit "$status"
}
trap finish EXIT
mkdir "$run_dir/bin"
export PATH="$run_dir/bin:$PATH"
curl -fsSL --retry 3 "https://dl.k8s.io/release/$KUBERNETES_VERSION/bin/linux/amd64/kubectl" -o "$run_dir/bin/kubectl"
curl -fsSL --retry 3 "https://dl.k8s.io/release/$KUBERNETES_VERSION/bin/linux/amd64/kubectl.sha256" -o "$run_dir/kubectl.sha256"
printf '%s  %s\n' "$(cat "$run_dir/kubectl.sha256")" "$run_dir/bin/kubectl" | sha256sum -c -
chmod +x "$run_dir/bin/kubectl"
oci ce cluster create-kubeconfig --cluster-id "$CLUSTER_ID" --file "$run_dir/kubeconfig" --region "$OCI_CLI_REGION" --token-version 2.0.0 --kube-endpoint PRIVATE_ENDPOINT >/dev/null
export KUBECONFIG=$run_dir/kubeconfig
# Bootstrap is separate: never create/adopt a namespace, service account or volume from this runner.
for resource in "serviceaccount/$service_account" "pvc/$pvc"; do
  kubectl -n "$namespace" get "$resource" -o json > "$run_dir/resource.json"
  jq -e --arg owner "$owner" '.metadata.labels["oke-llm/storage-owner"]==$owner' "$run_dir/resource.json" >/dev/null || { echo "Bootstrap ownership mismatch: $resource" >&2; exit 1; }
done
# Pending is valid for WaitForFirstConsumer; do not wait for Bound before creating its first consumer.
jq -e --arg class "$storage_class" --argjson gib "$(jq -er .scratch_gib "$input_dir/model.json")" '.metadata.deletionTimestamp==null and (.status.phase=="Bound" or .status.phase=="Pending") and .spec.storageClassName==$class and (.spec.accessModes|index("ReadWriteOnce"))!=null and (.spec.resources.requests.storage|capture("^(?<gib>[0-9]+)Gi$").gib|tonumber)>=$gib' "$run_dir/resource.json" >/dev/null
if [[ $(jq -r .status.phase "$run_dir/resource.json") == Pending ]]; then
  kubectl get storageclass "$storage_class" -o json > "$run_dir/storage-class.json"
  jq -e '.volumeBindingMode=="WaitForFirstConsumer"' "$run_dir/storage-class.json" >/dev/null || { echo 'Pending PVC requires a known WaitForFirstConsumer storage class; inspect claim/provisioner errors' >&2; exit 1; }
fi
for permission in 'create jobs.batch' 'delete jobs.batch' 'create configmaps' 'delete configmaps'; do
  read -r verb resource <<< "$permission"
  kubectl auth can-i "$verb" "$resource" -n "$namespace" --quiet || { echo "Missing namespaced permission: $permission" >&2; exit 1; }
done
selector=$(jq -r '.cpu_node_selector|to_entries|map(.key+"="+.value)|join(",")' "$input_dir/model.json")
kubectl get nodes -l "$selector" -o json > "$run_dir/cpu-nodes.json"
jq -e '
  [.items[] | select(.spec.unschedulable!=true and any(.status.conditions[]?;.type=="Ready" and .status=="True"))] as $nodes |
  ($nodes|length)>0 and all($nodes[];
    (.metadata.labels|has("nvidia.com/gpu") or has("nvidia.com/gpu.present") or has("oke-llm/allocation")|not) and
    ((.status.allocatable["nvidia.com/gpu"] // "0")|tonumber)==0
  )' "$run_dir/cpu-nodes.json" >/dev/null || { echo 'CPU pool selector must resolve to ready schedulable CPU nodes only; no staging Job was created' >&2; exit 1; }
kubectl -n "$namespace" create configmap "$configmap" --from-file="$input_dir/model.json" --from-file="$input_dir/download.sh" --from-file="$input_dir/validate.jq" >/dev/null
created_configmap=true
jq --arg name "$job" --arg configmap "$configmap" --arg image "$STAGING_IMAGE" --arg deadline "$JOB_DEADLINE_SECONDS" --arg run_id "$run_id" \
  -f "$input_dir/job.jq" "$input_dir/model.json" > "$run_dir/job.json"
# Fixed Job name atomically excludes concurrent executions against this PVC. Never delete a pre-existing Job.
kubectl create -f "$run_dir/job.json" >/dev/null
created_job=true
volume_checked=false
check_bound() {
  kubectl -n "$namespace" get "pvc/$pvc" -o json > "$run_dir/bound-pvc.json"
  jq -e --arg owner "$owner" '.metadata.labels["oke-llm/storage-owner"]==$owner and .metadata.deletionTimestamp==null and .status.phase=="Bound"' "$run_dir/bound-pvc.json" >/dev/null || { echo 'Scheduled/completed staging Job has no owned Bound PVC' >&2; return 1; }
  volume_checked=true
}
stop_at=$((SECONDS + JOB_DEADLINE_SECONDS + 300))
while (( SECONDS < stop_at )); do
  kubectl -n "$namespace" get job "$job" -o json > "$run_dir/job.json"
  if jq -e '.status.succeeded==1' "$run_dir/job.json" >/dev/null; then check_bound; exit 0; fi
  if jq -e 'any(.status.conditions[]?; .type=="Failed" and .status=="True")' "$run_dir/job.json" >/dev/null; then exit 1; fi
  if [[ "$volume_checked" == false ]]; then
    kubectl -n "$namespace" get pods -l "job-name=$job" -o json > "$run_dir/pods.json"
    if jq -e 'any(.items[]?;.spec.nodeName!=null and (.status.phase=="Running" or .status.phase=="Succeeded"))' "$run_dir/pods.json" >/dev/null; then check_bound; fi
  fi
  sleep 10
done
echo 'Staging Job exceeded its bounded deadline' >&2
exit 1
