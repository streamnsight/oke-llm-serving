#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
model_config=${MODEL_CONFIG:-runtime/config.json}
namespace=$(jq -er .namespace "$model_config")
release=$(jq -er .release "$model_config")
cluster=$(jq -er .platform.cluster_id "$model_config")
identity=$(jq -er .identity "$model_config")
owner=$(jq -er .ownership_token "$model_config")
timeout=$(jq -er .timeout_seconds "$model_config")
owner_name="oke-llm-owner-$(printf '%s' "$namespace/$release" | sha256sum | cut -c1-24)"
model_fail() { echo "$*" >&2; return 2; }
model_inputs() {
  local key platform_name platform_owner model_namespace
  for key in TP PP HOSTS_PER_REPLICA GPUS_PER_POD REPLICAS CONTEXT_LENGTH CONCURRENCY; do
    [[ ${!key:-} =~ ^[1-9][0-9]*$ ]] || model_fail "$key must be a positive integer" || return
  done
  [[ $MODEL_NAMESPACE == "$namespace" ]] || model_fail 'MODEL_NAMESPACE is an immutable onboarding boundary; create/onboard another stack to change it' || return
  [[ $MODEL_ID =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || model_fail 'MODEL_ID must be a Hugging Face repository ID' || return
  [[ $SERVING_IMAGE =~ ^[A-Za-z0-9][A-Za-z0-9./:_-]*@sha256:[a-f0-9]{64}$ && $MODEL_REVISION =~ ^[a-f0-9]{40}$ ]] || model_fail 'Use an immutable image digest and Hugging Face commit' || return
  # This adapter uses TP within each host and PP across LWS hosts. Other
  # distributed layouts require a separate explicit execution adapter.
  (( TP == GPUS_PER_POD && PP == HOSTS_PER_REPLICA )) || model_fail 'Native MP adapter requires GPUS_PER_POD=TP and HOSTS_PER_REPLICA=PP; cross-host TP/Ray require another adapter' || return
  if (( REPLICAS > 1 )); then
    jq -e .router_enabled "$model_config" >/dev/null || model_fail 'Multiple replicas require the prefix-aware router; enable it in the model stack before increasing REPLICAS' || return
  fi
  [[ $INFERENCE_PROBE == none || $INFERENCE_PROBE == completions || $INFERENCE_PROBE == chat ]] || model_fail 'Unsupported inference probe; select none or an explicit text probe' || return
  platform_name=$(jq -er .platform.platform_name "$model_config")
  platform_owner=$(printf '%s' "$platform_name/$cluster" | sha256sum | cut -c1-32)
  kubectl get namespace "$namespace" -o json > model-namespace.json
  jq -e --arg owner "$platform_owner" --arg platform "$platform_name" --arg cluster "$cluster" \
    '.metadata.labels["oke-llm/platform-owner"]==$owner and .metadata.labels["oke-llm/model-namespace"]=="true" and .metadata.annotations["oke-llm/platform-name"]==$platform and .metadata.annotations["oke-llm/cluster-id"]==$cluster' model-namespace.json >/dev/null || model_fail 'Namespace is not owned/onboarded by this platform' || return
}
model_geometry() {
  local hosts nodes gpus max_replicas required selector
  jq -e '.platform.allocation.gpu_pool_id | type=="string" and length>0' "$model_config" >/dev/null || model_fail 'GPU allocation is disabled or absent. Pipelines may be created in CPU debug mode, but model execution requires a real retained GPU pool' || return
  nodes=$(jq -er .platform.node_count "$model_config")
  gpus=$(jq -er .platform.gpu_count_per_host "$model_config")
  max_replicas=0
  if jq -e .autoscaling.enabled "$model_config" >/dev/null; then
    for key in MIN_REPLICAS MAX_REPLICAS TARGET_INFLIGHT; do
      [[ ${!key:-} =~ ^[1-9][0-9]*$ ]] || model_fail "$key must be a positive integer" || return
    done
    (( MIN_REPLICAS <= REPLICAS && REPLICAS <= MAX_REPLICAS )) || model_fail 'Autoscaling bounds must contain the configured initial replica count' || return
    [[ $PROMETHEUS_URL =~ ^https?://[A-Za-z0-9_.:/-]+$ ]] || model_fail 'Use a non-secret reachable Prometheus URL' || return
    max_replicas=$MAX_REPLICAS
  fi
  (( max_replicas < REPLICAS )) && max_replicas=$REPLICAS
  (( GPUS_PER_POD <= gpus && max_replicas * HOSTS_PER_REPLICA <= nodes * (gpus / GPUS_PER_POD) && HOSTS_PER_REPLICA <= nodes )) || model_fail 'Requested replicas/hosts/GPUs exceed complete model slots in the retained allocation; rerun discovery for larger infrastructure' || return
  selector=$(jq -er .platform.gpu_selector "$model_config")
  kubectl get nodes -l "$selector" -o json > allocation-nodes.json
  jq -e --argjson nodes "$nodes" --argjson gpus "$gpus" '[.items[]|select(.spec.unschedulable!=true and any(.status.conditions[]; .type=="Ready" and .status=="True"))|select((.status.allocatable["nvidia.com/gpu"]//"0"|tonumber)>=$gpus)]|length>=$nodes' allocation-nodes.json >/dev/null || model_fail 'Retained GPU allocation is not fully Ready with the expected allocatable GPU resources' || return
  if (( HOSTS_PER_REPLICA > 1 )); then
    local version minor
    version=$(jq -er .platform.kubernetes_version "$model_config")
    minor=${version#v1.}; minor=${minor%%.*}
    [[ $version == v1.* && $minor =~ ^[0-9]+$ ]] && (( minor >= 33 )) || model_fail 'Per-LWS-group host separation requires Kubernetes 1.33+ matchLabelKeys; use a supported cluster or a different placement adapter' || return
    jq -e '.platform.required_components|index("lws")!=null' "$model_config" >/dev/null || model_fail 'Multi-node model requires the platform LWS controller' || return
    kubectl get crd leaderworkersets.leaderworkerset.x-k8s.io -o json | jq -e 'any(.status.conditions[]; .type=="Established" and .status=="True")' >/dev/null
  fi
  if jq -e '.platform.transport.requires_rdma==true' "$model_config" >/dev/null; then
    local resource
    resource=$(jq -er '.platform.transport.rdma_resource_name|select(length>0)' "$model_config") || model_fail 'RDMA transport has no device resource name; validate the platform network plugin before serving' || return
    jq -e --arg resource "$resource" --argjson nodes "$nodes" '[.items[]|select((.status.allocatable[$resource]//"0"|tonumber)>0)]|length>=$nodes' allocation-nodes.json >/dev/null || model_fail 'Expected RDMA device resource is not advertised by every required GPU host' || return
  fi
}
model_platform_ready() {
  local entry name component_namespace mode expected deployment
  jq -e '.platform.components|type=="object"' "$model_config" >/dev/null || model_fail 'Binding has no shared-component generation descriptors. Regenerate the model ZIP from the current infrastructure publisher' || return
  jq -e '.platform as $p | all(($p.required_components//[])[]; $p.components[.]!=null)' "$model_config" >/dev/null || model_fail 'Binding is missing a required platform component descriptor' || return
  while IFS= read -r entry; do
    name=$(jq -er .key <<< "$entry")
    mode=$(jq -er .value.mode <<< "$entry")
    [[ $mode != retire ]] || model_fail "Required platform component $name is being retired" || return
    component_namespace=$(jq -er .value.namespace <<< "$entry")
    if [[ $mode == managed ]]; then
      kubectl -n "$component_namespace" get configmap "$(jq -er .value.owner_name <<< "$entry")" -o json > platform-owner.json
      expected=$(jq -er .value.generation <<< "$entry")
      jq -e --arg generation "$expected" '.data.generation==$generation and .data.status=="ready"' platform-owner.json >/dev/null || model_fail "Platform component $name is not ready at the bound generation" || return
    fi
    while IFS= read -r deployment; do
      kubectl -n "$component_namespace" get deployment "$deployment" -o json > platform-controller.json
      jq -e '.status.observedGeneration>=.metadata.generation and (.status.availableReplicas//0)>=(.spec.replicas//1) and any(.status.conditions[]; .type=="Available" and .status=="True")' platform-controller.json >/dev/null || model_fail "Platform controller $name/$deployment is unavailable" || return
    done < <(jq -r '.value.deployment_names[]' <<< "$entry")
  done < <(jq -c '.platform.components|to_entries[]' "$model_config")
}
model_storage() {
  local mode pvc scratch nodes
  mode=$(jq -er .storage.mode "$model_config")
  pvc=$(jq -r .storage.pvc_name "$model_config")
  if [[ $mode == direct_hf ]]; then
    jq -e '.storage.snapshot_bytes>0 or .storage.workspace_explicit==true' "$model_config" >/dev/null || model_fail 'Checkpoint download size is unknown. Supply a measured per-pod workspace_gib before deploying; the display default is not a validated estimate' || return
  fi
  if [[ $mode != direct_hf ]]; then
    [[ -n $pvc ]] || model_fail 'Staged/object storage is not a mounted model snapshot. Supply an existing retained model PVC and model path; the CPU staging scratch PVC cannot serve the model' || return
    scratch=$(jq -r '.platform.model_storage.scratch_pvc // empty' "$model_config")
    [[ -z $scratch || $pvc != "$scratch" ]] || model_fail 'The CPU staging scratch PVC is not a retained model serving volume' || return
    kubectl -n "$namespace" get pvc "$pvc" -o json > model-pvc.json
    jq -e '.status.phase=="Bound"' model-pvc.json >/dev/null || model_fail 'Existing model PVC is not Bound' || return
    nodes=$(jq -er .platform.node_count "$model_config")
    if (( nodes > 1 )); then
      jq -e 'any(.spec.accessModes[]; .=="ReadOnlyMany" or .=="ReadWriteMany")' model-pvc.json >/dev/null || model_fail 'A multi-host allocation requires a ROX/RWX serving PVC: Kubernetes may place model pods on different retained GPU hosts; RWO staging volumes are insufficient' || return
    fi
    if (( REPLICAS * HOSTS_PER_REPLICA > 1 )); then
      jq -e 'all(.spec.accessModes[]; .!="ReadWriteOncePod")' model-pvc.json >/dev/null || model_fail 'ReadWriteOncePod cannot serve multiple model pods' || return
    fi
    # A read-only mounted snapshot must contain its materialization marker.
    jq -e --arg revision "$MODEL_REVISION" '.metadata.annotations["oke-llm/model-revision"]==$revision' model-pvc.json >/dev/null || model_fail 'Existing model PVC lacks the expected immutable model-revision annotation' || return
  fi
}
model_ready_owner() {
  local settings
  settings=$(jq -cn --slurpfile config "$model_config" '(((($config[0].defaults|keys)-["INFERENCE_PROBE"])+["CHART_VERSION"])|map(. as $key|{key:$key,value:env[$key]})|from_entries)' | sha256sum | cut -d' ' -f1)
  kubectl -n "$namespace" get configmap "$owner_name" -o json > model-owner.json
  jq -e --arg owner "$owner" --arg generation "$DELIVERY_GENERATION" --arg settings "$settings" '.data.ownership_token==$owner and .data.generation==$generation and .data.status=="ready" and .data.settings_sha256==$settings' model-owner.json >/dev/null || model_fail 'The current model generation/settings are not validated; deploy and validate them first' || return
  helm status "$release" -n "$namespace" -o json > model-helm-status.json
  helm get metadata "$release" -n "$namespace" -o json > model-helm-metadata.json
  jq -e --slurpfile owner model-owner.json --slurpfile status model-helm-status.json '.status=="deployed" and .revision==$status[0].version and ($status[0].version|tostring)==$owner[0].data.helm_revision and (.version|ltrimstr("v"))==($owner[0].data.chart_version|ltrimstr("v")) and $status[0].info.status=="deployed"' model-helm-metadata.json >/dev/null || model_fail 'Helm revision/chart changed after validation; current generation must be validated again' || return
}
model_validate() {
  local endpoint port probe expected
  if (( HOSTS_PER_REPLICA > 1 )); then
    kubectl -n "$namespace" wait --for=condition=Available "leaderworkerset/$release" --timeout="${timeout}s"
    kubectl -n "$namespace" wait --for=condition=Progressing=false "leaderworkerset/$release" --timeout="${timeout}s"
  fi
  kubectl -n "$namespace" wait --for=condition=Ready pod -l "oke-llm/model=$identity" --timeout="${timeout}s"
  kubectl -n "$namespace" get pods -l "oke-llm/model=$identity" -o json > model-pods.json
  expected=$REPLICAS
  if jq -e .autoscaling.enabled "$model_config" >/dev/null; then expected=$MIN_REPLICAS; fi
  jq -e --arg image "$SERVING_IMAGE" --argjson expected "$((expected * HOSTS_PER_REPLICA))" '[.items[]|select(.metadata.deletionTimestamp==null)]|length >= $expected and all(.[]; any(.spec.containers[]; .name=="vllm" and .image==$image) and any(.status.conditions[]; .type=="Ready" and .status=="True"))' model-pods.json >/dev/null || model_fail 'Serving pod count, image identity or readiness does not match this model configuration' || return
  endpoint=$release; port=8000
  if jq -e .router_enabled "$model_config" >/dev/null; then
    kubectl -n "$namespace" rollout status "deployment/$release-deployment-router" --timeout="${timeout}s"
    endpoint="$release-router-service"; port=80
  fi
  kubectl -n "$namespace" port-forward "service/$endpoint" "27180:$port" > model-port-forward.log 2>&1 &
  model_forward_pid=$!
  trap 'kill "$model_forward_pid" 2>/dev/null || true' EXIT
  local attempt health_ready=false
  for attempt in {1..60}; do
    if curl -fsS --max-time 10 http://127.0.0.1:27180/health > model-health.txt; then health_ready=true; break; fi
    kill -0 "$model_forward_pid" 2>/dev/null || { cat model-port-forward.log >&2; return 2; }
    sleep 1
  done
  [[ $health_ready == true ]] || model_fail 'Serving endpoint never passed /health; model identity alone cannot establish readiness' || return
  curl -fsS --max-time 60 http://127.0.0.1:27180/v1/models > model-identities.json
  jq -e --arg model "$MODEL_ID" 'any(.data[]; .id==$model)' model-identities.json >/dev/null || model_fail 'Serving API did not advertise the expected model identity' || return
  probe=$INFERENCE_PROBE
  if [[ $probe != none ]]; then
    if [[ $probe == chat ]]; then
      jq -n --arg model "$MODEL_ID" '{model:$model,messages:[{role:"user",content:"Reply with a single word: ready"}],max_tokens:16}' > inference-request.json
      endpoint=chat/completions
    else
      jq -n --arg model "$MODEL_ID" '{model:$model,prompt:"The capital of France is",max_tokens:16}' > inference-request.json
      endpoint=completions
    fi
    curl -fsS --max-time "$timeout" -H 'Content-Type: application/json' --data-binary @inference-request.json "http://127.0.0.1:27180/v1/$endpoint" > inference-result.json
    jq -e '.choices|length>0' inference-result.json >/dev/null
  fi
  jq -n --arg model "$MODEL_ID" --arg revision "$MODEL_REVISION" --arg image "$SERVING_IMAGE" --arg probe "$probe" \
    '{status:"ready",model:$model,model_revision:$revision,image:$image,checks:["pod_readiness","image_identity","health","model_identity"],inference_probe:($probe|if .=="none" then "not_run; choose a task-specific probe" else . end),responses_conversation_persistence:false}' > model-validation.json
  kill "$model_forward_pid" 2>/dev/null || true
  wait "$model_forward_pid" 2>/dev/null || true
  trap - EXIT
}
