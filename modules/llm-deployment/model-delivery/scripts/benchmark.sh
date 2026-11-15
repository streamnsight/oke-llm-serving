#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
source runtime/common.sh
[[ $BENCHMARK_BACKEND == openai || $BENCHMARK_BACKEND == openai-chat ]] || model_fail 'No benchmark task/dataset adapter selected. For text generation choose openai or openai-chat explicitly; multimodal/STT/TTS need their own dataset adapter'
tokenizer=$(jq -r --arg model "$MODEL_ID" '.serving.recipe.args as $args | ($args|index("--tokenizer")) as $index | if $index==null then $model else $args[$index+1] end' "$model_config")
[[ $tokenizer == "$MODEL_ID" ]] || model_fail 'This recipe uses another tokenizer repository. Its immutable tokenizer revision needs a dedicated benchmark dataset adapter; refusing to download an unrelated model revision'
for key in BENCHMARK_REQUESTS BENCHMARK_INPUT_TOKENS BENCHMARK_OUTPUT_TOKENS; do
  [[ ${!key:-} =~ ^[1-9][0-9]*$ ]] || model_fail "$key must be a positive integer"
done
(( BENCHMARK_INPUT_TOKENS + BENCHMARK_OUTPUT_TOKENS + 128 <= CONTEXT_LENGTH )) || model_fail 'Benchmark token lengths plus template allowance exceed context length'
job="bench-$(printf '%s' "$OCI_DEPLOYMENT_ID" | sha256sum | cut -c1-24)"
cm="$job-input"
cleanup_job() {
  local code=$?
  trap - EXIT
  kubectl -n "$namespace" delete job "$job" --ignore-not-found --wait=false >/dev/null || code=1
  kubectl -n "$namespace" delete configmap "$cm" --ignore-not-found >/dev/null || code=1
  exit "$code"
}
trap cleanup_job EXIT
kubectl -n "$namespace" create configmap "$cm" --from-file=bench-client.sh=runtime/bench-client.sh --dry-run=client -o json | kubectl apply -f - >/dev/null
endpoint="http://$release.$namespace.svc:8000"
if jq -e .router_enabled "$model_config" >/dev/null; then endpoint="http://$release-router-service.$namespace.svc:80"; fi
jq -n --arg job "$job" --arg namespace "$namespace" --arg image "$(jq -er .benchmark_image "$model_config")" --arg cm "$cm" --arg endpoint "$endpoint" --slurpfile config "$model_config" \
  '{apiVersion:"batch/v1",kind:"Job",metadata:{name:$job,namespace:$namespace},spec:{backoffLimit:0,activeDeadlineSeconds:3000,ttlSecondsAfterFinished:3600,template:{spec:{restartPolicy:"Never",automountServiceAccountToken:false,affinity:{nodeAffinity:{requiredDuringSchedulingIgnoredDuringExecution:{nodeSelectorTerms:[{matchExpressions:[{key:"nvidia.com/gpu.present",operator:"DoesNotExist"},{key:"nvidia.com/gpu",operator:"DoesNotExist"},{key:"oke-llm/allocation",operator:"DoesNotExist"}]}]}}},containers:[{name:"benchmark",image:$image,command:["bash","/benchmark/bench-client.sh"],env:((["MODEL_ID","MODEL_REVISION","CONCURRENCY","BENCHMARK_BACKEND","BENCHMARK_REQUESTS","BENCHMARK_INPUT_TOKENS","BENCHMARK_OUTPUT_TOKENS"]|map(. as $key|{name:$key,value:env[$key]}))+[{name:"BASE_URL",value:$endpoint}]+(if ($config[0].hf_token_secret//"")!="" then [{name:"HF_TOKEN",valueFrom:{secretKeyRef:{name:$config[0].hf_token_secret,key:"token"}}}] else [] end)),resources:{requests:{cpu:"2",memory:"4Gi","ephemeral-storage":"2Gi"},limits:{memory:"8Gi","ephemeral-storage":"4Gi"}},volumeMounts:[{name:"benchmark",mountPath:"/benchmark",readOnly:true}]}],volumes:[{name:"benchmark",configMap:{name:$cm}}]}}}}' > benchmark-job.json
kubectl create -f benchmark-job.json >/dev/null
if ! kubectl -n "$namespace" wait --for=condition=Complete "job/$job" --timeout=3100s; then
  kubectl -n "$namespace" logs "job/$job" >&2 || true
  model_fail 'vLLM benchmark Job failed; Job logs are shown above in the deployment log'
fi
kubectl -n "$namespace" logs "job/$job" > benchmark.log
awk '/^BENCHMARK_RESULT_BEGIN$/{capture=1;next}/^BENCHMARK_RESULT_END$/{capture=0}capture' benchmark.log > benchmark-result.json
jq -e 'type=="object"' benchmark-result.json >/dev/null
echo 'vLLM benchmark result:'
cat benchmark-result.json
oci artifacts generic artifact upload-by-path --repository-id "$DELIVERY_RESULT_REPOSITORY" --artifact-path "$identity/model/$DELIVERY_GENERATION/$OCI_DEPLOYMENT_ID/vllm-benchmark.json" --artifact-version "$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}" --content-body benchmark-result.json >/dev/null
