#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# OCI DevOps Shell stage entry point; config/render/benchmark are bundled inline by Terraform.
set -euo pipefail
for tool in jq curl tar sha256sum oci; do command -v "$tool" >/dev/null || { echo "Missing DevOps tool: $tool" >&2; exit 2; }; done
run_dir=$(mktemp -d)
stage_started=$(date +%s)
cd "$run_dir"
printf '%s' "$CONFIG_B64" | base64 --decode > config.json
printf '%s' "$RENDER_B64" | base64 --decode > render.jq
printf '%s' "$BENCHMARK_B64" | base64 --decode > benchmark.sh
name=$(jq -r .name config.json)
namespace=$(jq -r .namespace config.json)
region=$(jq -r .region config.json)
job_name="${name}-${MODE}-$(date -u +%s)-$RANDOM"
jq --arg job "$job_name" '.job_name=$job' config.json > rendered-config.json
jq -f render.jq rendered-config.json > rendered.json
export OCI_CLI_AUTH=resource_principal
export OCI_CLI_REGION="$region"
forward_pid=''
archive() {
  local code=$?
  trap - EXIT
  if command -v kubectl >/dev/null && [[ -n "${KUBECONFIG:-}" ]]; then kubectl delete "job/$job_name" "configmap/$job_name" -n "$namespace" --ignore-not-found --wait=false >/dev/null 2>&1 || true; fi
  [[ -z "$forward_pid" ]] || kill "$forward_pid" 2>/dev/null || true
  if [[ ! -s report.json ]] || ! jq -e 'type=="object" and has("status")' report.json >/dev/null 2>&1; then jq -n --arg mode "$MODE" --argjson code "$code" '{mode:$mode,status:(if $code==0 then "passed" else "failed" end),exit_code:$code}' > report.json; fi
  jq --argjson code "$code" --slurpfile spec config.json '. + {deployment_spec:$spec[0],stage_exit_code:$code,status:(if $code==0 then .status else "failed" end)}' report.json > provenance-report.json
  local bucket storage_namespace prefix
  bucket=$(jq -r .artifact_bucket config.json)
  storage_namespace=$(jq -r .storage_namespace config.json)
  prefix="$name/$(jq -r .assessment_id config.json)/${OCI_DEVOPS_DEPLOYMENT_ID:-$job_name}/$MODE"
  for artifact in provenance-report.json raw-results.log benchmark-result.json context-test.json context-response.json pods.json rdma-evidence.log helm-releases.json; do
    [[ -s "$artifact" ]] || continue
    oci os object put --namespace-name "$storage_namespace" --bucket-name "$bucket" --name "$prefix/$artifact" --file "$artifact" --force >/dev/null || code=1
  done
  if [[ "$MODE" != benchmark ]]; then
    if [[ "$MODE" == validate && $code -eq 0 ]]; then cp provenance-report.json validation-marker.json
    else jq -n --argjson code "$code" '{status:(if $code==0 then "pending_validation" else "failed" end)}' > validation-marker.json; fi
    oci os object put --namespace-name "$storage_namespace" --bucket-name "$bucket" --name "$name/$(jq -r .specification_hash config.json)/validated.json" --file validation-marker.json --force >/dev/null || code=1
  fi
  echo "Evidence: oci://$bucket/$prefix/"
  exit "$code"
}
trap archive EXIT
if [[ "$MODE" != benchmark ]]; then
  printf '{"status":"in_progress"}\n' > validation-marker.json
  oci os object put --namespace-name "$(jq -r .storage_namespace config.json)" --bucket-name "$(jq -r .artifact_bucket config.json)" --name "$name/$(jq -r .specification_hash config.json)/validated.json" --file validation-marker.json --force >/dev/null
fi
mkdir bin
export PATH="$run_dir/bin:$PATH"
# Download release-pinned CLI binaries; verify their published checksums.
kube_version=$(jq -r .kubernetes_version config.json)
curl -fsSL --retry 3 "https://dl.k8s.io/release/$kube_version/bin/linux/amd64/kubectl" -o bin/kubectl
curl -fsSL --retry 3 "https://dl.k8s.io/release/$kube_version/bin/linux/amd64/kubectl.sha256" -o kubectl.sha256
printf '%s  %s\n' "$(cat kubectl.sha256)" bin/kubectl | sha256sum --check
chmod +x bin/kubectl
helm_version=$(jq -r .components.helm_version config.json)
curl -fsSL --retry 3 "https://get.helm.sh/helm-$helm_version-linux-amd64.tar.gz" -o helm.tgz
curl -fsSL --retry 3 "https://get.helm.sh/helm-$helm_version-linux-amd64.tar.gz.sha256sum" -o helm.sha256
printf '%s  helm.tgz\n' "$(cut -d ' ' -f 1 helm.sha256)" | sha256sum --check
tar -xzf helm.tgz
mv linux-amd64/helm bin/helm
oci ce cluster create-kubeconfig --cluster-id "$(jq -r .cluster_id config.json)" --file "$run_dir/kubeconfig" --region "$region" --token-version 2.0.0 --kube-endpoint PRIVATE_ENDPOINT >/dev/null
export KUBECONFIG="$run_dir/kubeconfig"
control_selector=$(jq -cn --arg name "$name" '{"oke-llm/control":$name}')
node_selector="oke-llm/allocation=$name"
pp=$(jq -r .pipeline_parallel_size config.json)
replicas=$(jq -r .replicas config.json)
wait_gpus() {
  for attempt in $(seq 1 180); do
    kubectl get nodes -l "$node_selector" -o json > nodes.json
    if jq -e --slurpfile c config.json '(.items|length)>=$c[0].node_count and all(.items[]; any(.status.conditions[]; .type=="Ready" and .status=="True") and ((.status.allocatable["nvidia.com/gpu"] // "0")|tonumber)>=$c[0].tensor_parallel_size and (if $c[0].requires_rdma then ((.status.allocatable["rdma/rdma_shared_device_a"] // "0")|tonumber)>0 else true end))' nodes.json >/dev/null; then return; fi
    sleep 10
  done
  echo 'GPU/RDMA nodes did not become allocatable.' >&2; return 1
}
if [[ "$MODE" == deploy ]]; then
  if [[ $(jq -r .install_gpu_operator config.json) == true ]]; then
    helm upgrade --install "${name}-gpu-operator" gpu-operator --repo "$(jq -r .components.gpu_operator.repository config.json)" --version "$(jq -r .components.gpu_operator.version config.json)" --namespace gpu-operator --create-namespace --set driver.enabled=false --set toolkit.enabled=false --set-json "operator.nodeSelector=$control_selector" --wait --timeout 20m
  fi
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
  if [[ $(jq -r .requires_rdma config.json) == true ]]; then
    jq .rdma_manifest rendered.json | kubectl apply -f -
    kubectl rollout status "daemonset/${name}-rdma" -n kube-system --timeout=600s
  fi
  wait_gpus
  if [[ "$pp" -gt 1 ]]; then
    helm upgrade --install lws "$(jq -r .components.lws.chart config.json)" --version "$(jq -r .components.lws.version config.json)" --namespace lws-system --create-namespace --set-json "nodeSelector=$control_selector" --wait --timeout 10m
    jq .multi_node_manifest rendered.json | kubectl apply -f -
    ready=false
    for attempt in $(seq 1 180); do
      if kubectl get leaderworkerset "$name" -n "$namespace" -o json | jq -e --argjson replicas "$replicas" '(.status.readyReplicas // 0)>=$replicas' >/dev/null; then ready=true; break; fi
      sleep 10
    done
    [[ "$ready" == true ]] || { echo 'Distributed model groups did not become ready.' >&2; exit 1; }
  fi
  jq .helm_values rendered.json > values.json
  helm upgrade --install "$name" vllm-stack --repo "$(jq -r .components.production_stack.repository config.json)" --version "$(jq -r .components.production_stack.version config.json)" --namespace "$namespace" -f values.json --wait --timeout 30m
  helm list --all-namespaces -o json > helm-releases.json
  jq -n --argjson seconds "$(($(date +%s)-stage_started))" '{mode:"deploy",status:"passed",runtime_validation:"pending",deployment_readiness_seconds:$seconds}' > report.json
  exit
fi
wait_gpus
kubectl get pods -n "$namespace" -l "oke-llm/model=$name" -o json > pods.json
jq -e --slurpfile c config.json '(.items|length)==$c[0].node_count and ([.items[].spec.nodeName]|unique|length)==$c[0].node_count and all(.items[]; any(.status.conditions[]?; .type=="Ready" and .status=="True"))' pods.json >/dev/null
# Bind this run to the deployed specification and resolved runtime digest.
jq -e --slurpfile c config.json 'all(.items[]; any(.spec.containers[]; .image|endswith($c[0].engine_image|split("@")[1])))' pods.json >/dev/null
jq -e --slurpfile c config.json 'all(.items[]; .metadata.labels["oke-llm/specification"]==$c[0].specification_hash[:32] and any(.status.containerStatuses[]?; .imageID|endswith($c[0].engine_image|split("@")[1])))' pods.json >/dev/null
if [[ "$MODE" == benchmark ]]; then
  oci os object get --namespace-name "$(jq -r .storage_namespace config.json)" --bucket-name "$(jq -r .artifact_bucket config.json)" --name "$name/$(jq -r .specification_hash config.json)/validated.json" --file prior-validation.json >/dev/null
  jq -e '.status=="passed"' prior-validation.json >/dev/null
fi
if [[ "$MODE" == validate ]]; then
  kubectl port-forward -n "$namespace" "service/${name}-router-service" 18000:80 > forward.log 2>&1 &
  forward_pid=$!
  for attempt in $(seq 1 60); do if curl -fsS http://127.0.0.1:18000/v1/models > models.json; then break; fi; sleep 2; done
  jq -e 'any(.data[]; .id=="model")' models.json >/dev/null
  jq -n '{model:"model",messages:[{role:"user",content:"Reply with a short greeting."}],max_tokens:16,temperature:0}' > request.json
  curl -fsS --max-time 180 -H 'Content-Type: application/json' --data-binary @request.json http://127.0.0.1:18000/v1/chat/completions > response.json
  jq -e '.choices[0].message.content|type=="string" and length>0' response.json >/dev/null
  jq --slurpfile response response.json '.messages += [$response[0].choices[0].message,{role:"user",content:"What did I just ask?"}]' request.json > followup.json
  curl -fsS --max-time 180 -H 'Content-Type: application/json' --data-binary @followup.json http://127.0.0.1:18000/v1/chat/completions > followup-response.json
  jq -e '.choices[0].message.content|type=="string" and length>0' followup-response.json >/dev/null
  # The official vLLM benchmark exercises streaming below.
  kill "$forward_pid"; forward_pid=''
  # Inspect a leader directly for tokenizer/context checks; the router is tested above.
  leader=$(jq -r '[.items[]|select(.metadata.labels.role=="leader" or (.metadata.labels.role==null))][0].metadata.name' pods.json)
  kubectl port-forward -n "$namespace" "pod/$leader" 18000:8000 > forward-engine.log 2>&1 &
  forward_pid=$!
  for attempt in $(seq 1 60); do if curl -fsS http://127.0.0.1:18000/health >/dev/null; then break; fi; sleep 2; done
  context=$(jq -r .context_length config.json)
  low=1; high=$((context*4)); best=1; best_count=0
  while [[ $low -le $high ]]; do
    middle=$(((low+high)/2))
    jq -n --argjson words "$middle" '{model:"model",messages:[{role:"user",content:("hello "*$words)}],add_generation_prompt:true,chat_template_kwargs:{enable_thinking:false}}' > tokenize-request.json
    status=$(curl -sS --max-time 60 -o tokens.json -w '%{http_code}' -H 'Content-Type: application/json' --data-binary @tokenize-request.json http://127.0.0.1:18000/tokenize)
    if [[ "$status" == 400 ]] && jq -e '(.error.message // .message // "")|test("(?i)(context|maximum|too long)")' tokens.json >/dev/null; then high=$((middle-1)); continue; fi
    [[ "$status" == 200 ]] || { echo "Tokenizer validation failed: HTTP $status" >&2; exit 1; }
    jq -e --argjson context "$context" '.count>0 and .max_model_len==$context' tokens.json >/dev/null
    count=$(jq -r .count tokens.json)
    if [[ $count -le $((context-64)) ]]; then best=$middle; best_count=$count; low=$((middle+1)); else high=$((middle-1)); fi
  done
  [[ $best_count -gt 0 ]] || { echo 'Could not construct a near-limit context request.' >&2; exit 1; }
  jq -n --argjson words "$best" '{model:"model",messages:[{role:"user",content:("hello "*$words)}],max_tokens:16,temperature:0,chat_template_kwargs:{enable_thinking:false}}' > context-request.json
  curl -fsS --max-time 600 -H 'Content-Type: application/json' --data-binary @context-request.json http://127.0.0.1:18000/v1/chat/completions > context-response.json
  jq -e '.usage.prompt_tokens>0 and (.choices[0].message.content|type=="string" and length>0)' context-response.json >/dev/null
  jq -n --argjson configured "$context" --argjson tested "$best_count" '{configured_context:$configured,tokenized_prompt_tokens:$tested,output_token_limit:16}' > context-test.json
  kill "$forward_pid"; forward_pid=''
fi
base_url="http://${name}-router-service.${namespace}.svc.cluster.local"
jq --arg mode "$MODE" --arg base "$base_url" '. + {mode:$mode,base_url:$base}' config.json > client-config.json
kubectl create configmap "$job_name" -n "$namespace" --from-file=benchmark.sh --from-file=config.json=client-config.json --dry-run=client -o yaml | kubectl apply -f -
jq .benchmark_job rendered.json | kubectl apply -f -
job_passed=false
for attempt in $(seq 1 360); do
  kubectl get job "$job_name" -n "$namespace" -o json > job.json
  if jq -e '(.status.failed // 0)>0' job.json >/dev/null; then break; fi
  if jq -e '(.status.succeeded // 0)>0' job.json >/dev/null; then job_passed=true; break; fi
  sleep 10
done
kubectl logs "job/$job_name" -n "$namespace" > raw-results.log 2>&1 || true
awk '/^BENCHMARK_RESULT_BEGIN$/{capture=1;next}/^BENCHMARK_RESULT_END$/{capture=0}capture' raw-results.log > benchmark-result.json
expected=$(jq -r 'if .mode=="validate" then .concurrency else .benchmark_requests end' client-config.json)
jq -e --argjson expected "$expected" '.completed==$expected and ([.errors[]? | select(. != "" and . != null)] | length)==0' benchmark-result.json >/dev/null
[[ "$job_passed" == true ]] || exit 1
jq -n --slurpfile result benchmark-result.json --arg mode "$MODE" '{mode:$mode,status:"passed",tool:"vllm bench serve",native_result:$result[0]}' > report.json
if [[ $(jq -r .requires_rdma config.json) == true ]]; then
  : > rdma-evidence.log
  while IFS= read -r pod; do kubectl logs "$pod" -n "$namespace" --all-containers=true >> rdma-evidence.log; done < <(jq -r '.items[].metadata.name' pods.json)
  grep -Eq 'NET/IB : Using|Using network IB' rdma-evidence.log || { echo 'Could not confirm NCCL selected RDMA; inspect the archived logs.' >&2; exit 1; }
fi
if [[ "$MODE" == benchmark ]]; then
  oci os object get --namespace-name "$(jq -r .storage_namespace config.json)" --bucket-name "$(jq -r .artifact_bucket config.json)" --name "$name/$(jq -r .specification_hash config.json)/validated.json" --file prior-validation.json >/dev/null
  jq -e '.status=="passed"' prior-validation.json >/dev/null
fi
if [[ "$MODE" == validate ]]; then
  jq --slurpfile context context-test.json '. + {mode:"validate",checks:{node_placement:"passed",model_listing:"passed",chat_inference:"passed",client_supplied_history:"passed",streaming:"passed",requested_concurrency:"passed"},responses_conversation_persistence:"not_implemented",maximum_context_test:$context[0]}' report.json > validation.json
  mv validation.json report.json
fi
# Keep CPU benchmark jobs/configmaps out of the steady-state namespace after evidence capture.
kubectl delete "job/$job_name" "configmap/$job_name" -n "$namespace" --ignore-not-found
