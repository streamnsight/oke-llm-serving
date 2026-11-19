#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
source runtime/common.sh
export BENCHMARK_MODE=${BENCHMARK_MODE:-quick} BENCHMARK_REQUESTS=${BENCHMARK_REQUESTS:-auto}
export BENCHMARK_INPUT_TOKENS=${BENCHMARK_INPUT_TOKENS:-auto} BENCHMARK_OUTPUT_TOKENS=${BENCHMARK_OUTPUT_TOKENS:-128}
export BENCHMARK_PREFIX_TOKENS=${BENCHMARK_PREFIX_TOKENS:-auto} BENCHMARK_MAX_CONCURRENCY=${BENCHMARK_MAX_CONCURRENCY:-auto} BENCHMARK_MAX_SECONDS=${BENCHMARK_MAX_SECONDS:-auto}
[[ $BENCHMARK_BACKEND == openai || $BENCHMARK_BACKEND == openai-chat ]] || model_fail 'No benchmark task/dataset adapter selected. For text generation choose openai or openai-chat explicitly; multimodal/STT/TTS need their own dataset adapter'
tokenizer=$(jq -r --arg model "$MODEL_ID" '.serving.recipe.args as $args | ($args|index("--tokenizer")) as $index | if $index==null then $model else $args[$index+1] end' "$model_config")
[[ $tokenizer == "$MODEL_ID" ]] || model_fail 'This recipe uses another tokenizer repository. Its immutable tokenizer revision needs a dedicated benchmark dataset adapter; refusing to download an unrelated model revision'
python3 runtime/benchmark.py --plan > benchmark-plan.json
printf 'Benchmark workload plan: '; cat benchmark-plan.json
job_seconds=$(jq -er .job_seconds benchmark-plan.json)
job="bench-$(printf '%s' "$OCI_DEPLOYMENT_ID" | sha256sum | cut -c1-24)"
cm="$job-input"
log_pid=
cleanup_job() {
  local code=$? cleanup_code=0
  trap - EXIT
  if [[ -n $log_pid ]]; then kill "$log_pid" 2>/dev/null || true; wait "$log_pid" 2>/dev/null || true; fi
  kubectl -n "$namespace" delete job "$job" --ignore-not-found --wait=false >/dev/null || cleanup_code=1
  kubectl -n "$namespace" delete configmap "$cm" --ignore-not-found >/dev/null || cleanup_code=1
  (( code != 0 )) || code=$cleanup_code
  exit "$code"
}
trap cleanup_job EXIT
endpoint="http://$(model_http_service).$namespace.svc:8000"
if jq -e .router_enabled "$model_config" >/dev/null; then endpoint="http://$release-router-service.$namespace.svc:80"; fi
# Metrics are optional, inference and benchmark failures remain authoritative.
export BENCHMARK_METRICS_URLS BENCHMARK_PD_ENABLED
BENCHMARK_PD_ENABLED=$(jq -r '.disaggregation.enabled//false' "$model_config")
kubectl -n "$namespace" get pods -l "oke-llm/model=$identity,oke-llm/endpoint=true" -o json > benchmark-metrics-pods.json || echo '{"items":[]}' > benchmark-metrics-pods.json
jq '[.items[] | select(.metadata.deletionTimestamp==null and any(.status.conditions[]?; .type=="Ready" and .status=="True")) | select(.status.podIP!=null) | {url:"http://\(.status.podIP):8000/metrics",role:(.metadata.labels["oke-llm/role"]//"aggregated"),pod:.metadata.name}]' benchmark-metrics-pods.json > benchmark-metrics-targets.json
BENCHMARK_METRICS_URLS=$(jq -r 'map(.url)|join(",")' benchmark-metrics-targets.json)
cm_files=(--from-file=bench-client.sh=runtime/bench-client.sh --from-file=benchmark.py=runtime/benchmark.py --from-file=metrics-targets.json=benchmark-metrics-targets.json)
if [[ $BENCHMARK_PD_ENABLED == true && -f runtime/pd_observe.py ]]; then cm_files+=(--from-file=pd_observe.py=runtime/pd_observe.py); fi
kubectl -n "$namespace" create configmap "$cm" "${cm_files[@]}" --dry-run=client -o json | kubectl apply -f - >/dev/null
jq -n --arg job "$job" --arg namespace "$namespace" --arg image "$(jq -er .benchmark_image "$model_config")" --arg cm "$cm" --arg endpoint "$endpoint" --argjson deadline "$job_seconds" --slurpfile config "$model_config" \
  '{apiVersion:"batch/v1",kind:"Job",metadata:{name:$job,namespace:$namespace},spec:{backoffLimit:0,activeDeadlineSeconds:$deadline,ttlSecondsAfterFinished:3600,template:{spec:{restartPolicy:"Never",automountServiceAccountToken:false,affinity:{nodeAffinity:{requiredDuringSchedulingIgnoredDuringExecution:{nodeSelectorTerms:[{matchExpressions:[{key:"nvidia.com/gpu.present",operator:"DoesNotExist"},{key:"nvidia.com/gpu",operator:"DoesNotExist"},{key:"oke-llm/allocation",operator:"DoesNotExist"}]}]}}},containers:[{name:"benchmark",image:$image,command:["bash","/benchmark/bench-client.sh"],env:((["MODEL_ID","MODEL_REVISION","CONCURRENCY","REPLICAS","CONTEXT_LENGTH","BENCHMARK_MODE","BENCHMARK_BACKEND","BENCHMARK_REQUESTS","BENCHMARK_INPUT_TOKENS","BENCHMARK_OUTPUT_TOKENS","BENCHMARK_PREFIX_TOKENS","BENCHMARK_MAX_CONCURRENCY","BENCHMARK_MAX_SECONDS","BENCHMARK_METRICS_URLS","BENCHMARK_PD_ENABLED"]|map(. as $key|{name:$key,value:env[$key]}))+[{name:"BASE_URL",value:$endpoint},{name:"PYTHONUNBUFFERED",value:"1"}]+(if ($config[0].hf_token_secret//"")!="" then [{name:"HF_TOKEN",valueFrom:{secretKeyRef:{name:$config[0].hf_token_secret,key:"token"}}}] else [] end)),resources:{requests:{cpu:"2",memory:"4Gi","ephemeral-storage":"2Gi"},limits:{memory:"8Gi","ephemeral-storage":"4Gi"}},volumeMounts:[{name:"benchmark",mountPath:"/benchmark",readOnly:true}]}],volumes:[{name:"benchmark",configMap:{name:$cm}}]}}}}' > benchmark-job.json
kubectl create -f benchmark-job.json >/dev/null
kubectl -n "$namespace" logs -f "job/$job" --pod-running-timeout=300s &
log_pid=$!
stop=$((SECONDS + job_seconds + 60))
while (( SECONDS < stop )); do
  kubectl -n "$namespace" get job "$job" -o json > benchmark-job-status.json
  if jq -e 'any(.status.conditions[]?; .type=="Failed" and .status=="True") or (.status.failed//0)>0' benchmark-job-status.json >/dev/null; then
    kubectl -n "$namespace" logs "job/$job" >&2 || true
    model_fail 'vLLM benchmark Job failed; partial summaries and Job logs are in the deployment log'
  fi
  if jq -e 'any(.status.conditions[]?; .type=="Complete" and .status=="True")' benchmark-job-status.json >/dev/null; then
    if ! wait "$log_pid"; then kubectl -n "$namespace" logs "job/$job"; fi
    log_pid=
    echo 'Benchmark completed; aggregate results are retained in this deployment log. No result artifact uploaded.'
    exit 0
  fi
  sleep 5
done
kubectl -n "$namespace" logs "job/$job" >&2 || true
model_fail 'vLLM benchmark Job exceeded its bounded deadline'
