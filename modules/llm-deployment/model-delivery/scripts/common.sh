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
  local key expected platform_name platform_owner model_namespace image_registry
  for key in TP PP HOSTS_PER_REPLICA GPUS_PER_POD REPLICAS CONTEXT_LENGTH CONCURRENCY; do
    [[ ${!key:-} =~ ^[1-9][0-9]*$ ]] || model_fail "$key must be a positive integer" || return
  done
  for key in MODEL_PROJECT_ID MODEL_CLUSTER_ID MODEL_PLATFORM_NAME MODEL_GPU_POOL_ID; do
    # Metadata-only stack creation may precede allocation. Runtime arguments
    # cannot change the cluster/project/namespace trust boundary approved later.
    expected=$(jq -r --arg key "$key" '.defaults[$key] // empty' "$model_config")
    [[ -z $expected || ${!key:-} == "$expected" ]] || model_fail "$key is an immutable onboarding boundary" || return
  done
  [[ $MODEL_NAMESPACE == "$namespace" ]] || model_fail 'MODEL_NAMESPACE is an immutable onboarding boundary; create/onboard another stack to change it' || return
  [[ $MODEL_ID =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || model_fail 'MODEL_ID must be a Hugging Face repository ID' || return
  [[ $SERVING_IMAGE =~ ^[A-Za-z0-9][A-Za-z0-9./:_-]*@sha256:[a-f0-9]{64}$ ]] || model_fail 'Use an immutable serving image digest' || return
  [[ $MODEL_REVISION =~ ^[a-f0-9]{40}$ || $MODEL_REVISION == main ]] || model_fail 'MODEL_REVISION must be a 40-character Hugging Face commit or exactly main for direct_hf serving' || return
  [[ $MODEL_REVISION != main || $(jq -er .storage.mode "$model_config") == direct_hf ]] || model_fail 'MODEL_REVISION=main is mutable and supported only with direct_hf; retained PVC and staged snapshots require an immutable commit' || return
  image_registry=${SERVING_IMAGE%%/*}
  [[ $SERVING_IMAGE == */* && ( $image_registry == *.* || $image_registry == *:* || $image_registry == localhost ) ]] || model_fail 'SERVING_IMAGE must include its registry, for example docker.io/vllm/vllm-openai@sha256:<digest>. Short image names cannot be resolved interactively by CRI-O; retain the selected digest' || return
  [[ ${VLLM_USE_RUST_FRONTEND:-} == 0 || ${VLLM_USE_RUST_FRONTEND:-} == 1 ]] || model_fail 'VLLM_USE_RUST_FRONTEND must be 0 (Python default) or 1 (explicit Rust opt-in); validate model and chat-template compatibility before enabling Rust' || return
  # This adapter uses TP within each host and PP across LWS hosts. Other
  # distributed layouts require a separate explicit execution adapter.
  (( TP == GPUS_PER_POD && PP == HOSTS_PER_REPLICA )) || model_fail 'Native MP adapter requires GPUS_PER_POD=TP and HOSTS_PER_REPLICA=PP; cross-host TP/Ray require another adapter' || return
  if (( REPLICAS > 1 )); then
    jq -e .router_enabled "$model_config" >/dev/null || model_fail 'Multiple replicas require a router; select prefixaware or compatible kvaware routing before increasing REPLICAS' || return
  fi
  [[ $INFERENCE_PROBE == none || $INFERENCE_PROBE == completions || $INFERENCE_PROBE == chat ]] || model_fail 'Unsupported inference probe; select none or an explicit text probe' || return
  if jq -e '.lmcache.enabled // false' "$model_config" >/dev/null; then
    (( HOSTS_PER_REPLICA == 1 )) || model_fail 'LMCache currently supports single-host TP only' || return
    # The buffer and controller worker ports are fixed in the frozen profile.
    [[ $TP == "$(jq -r .defaults.TP "$model_config")" ]] || model_fail 'Changing TP with LMCache requires a stack Apply to resize host memory and worker ports' || return
  fi
  platform_name=$(jq -er .platform.platform_name "$model_config")
  platform_owner=$(printf '%s' "$platform_name/$cluster" | sha256sum | cut -c1-32)
  kubectl get namespace "$namespace" -o json > model-namespace.json || { model_fail "Model namespace is not accessible. Run trusted $platform_name-model-onboarding with this model project and exact pipeline IDs after infrastructure exists"; return 2; }
  jq -e --arg owner "$platform_owner" --arg platform "$platform_name" --arg cluster "$cluster" --arg project "$(jq -r .platform.project_id "$model_config")" --arg mode "$(jq -r '.platform.binding_mode // "bound"' "$model_config")" \
    '.metadata.labels["oke-llm/platform-owner"]==$owner and .metadata.labels["oke-llm/model-namespace"]=="true" and .metadata.annotations["oke-llm/platform-name"]==$platform and .metadata.annotations["oke-llm/cluster-id"]==$cluster and ($mode!="runtime" or .metadata.annotations["oke-llm/model-project-id"]==$project)' model-namespace.json >/dev/null || model_fail 'Namespace is not owned/onboarded by this platform' || return
}
model_pool() {
  local pool compartment platform shape expected_ad compute_cluster
  [[ $(jq -r '.platform.binding_mode // "bound"' "$model_config") == runtime ]] || return 0
  pool=$(jq -r '.platform.allocation.gpu_pool_id // empty' "$model_config")
  compartment=$(jq -er '.platform.gpu_pool_compartment_id // .platform.cluster_compartment_id' "$model_config")
  platform=$(jq -er .platform.platform_name "$model_config")
  shape=$(jq -er .platform.gpu_shape "$model_config")
  expected_ad=$(jq -r '.platform.availability_domain // empty' "$model_config")
  if [[ -z $pool ]]; then
    oci ce node-pool list --cluster-id "$cluster" --compartment-id "$compartment" --all > model-pools.json
    jq --arg cluster "$cluster" --arg platform "$platform" --arg shape "$shape" '[.data[] | select(.["cluster-id"]==$cluster and .["node-shape"]==$shape and any(.["initial-node-labels"][]?;.key=="oke-llm/allocation" and .value==$platform) and (.["freeform-tags"]["oke-llm-allocation"]|type=="string" and length>0))]' model-pools.json > matching-pools.json
    if [[ $(jq length matching-pools.json) -gt 1 && -n $expected_ad ]]; then
      jq --arg ad "$expected_ad" '[.[]|select(any(.["node-config-details"]["placement-configs"][]?;.["availability-domain"]==$ad))]' matching-pools.json > preferred-pools.json
      if [[ $(jq length preferred-pools.json) == 1 ]]; then mv preferred-pools.json matching-pools.json; fi
    fi
    [[ $(jq length matching-pools.json) == 1 ]] || model_fail 'Expected exactly one owned GPU pool for this cluster/platform/shape. Allocate infrastructure first, or select the exact retained pool in the model stack' || return
    pool=$(jq -er '.[0].id' matching-pools.json)
  fi
  oci ce node-pool get --node-pool-id "$pool" > model-pool.json
  jq -e --arg id "$pool" --arg cluster "$cluster" --arg platform "$platform" --arg shape "$shape" '
    .data | .id==$id and .["cluster-id"]==$cluster and .["lifecycle-state"]=="ACTIVE" and .["node-shape"]==$shape and
    any(.["initial-node-labels"][]?;.key=="oke-llm/allocation" and .value==$platform) and (.["freeform-tags"]["oke-llm-allocation"] | type=="string" and length>0)
  ' model-pool.json >/dev/null || model_fail 'GPU pool is not ACTIVE or does not match the selected cluster, shape and managed allocation identity' || return
  # A discovery AD limits a NEW allocation, not reuse of already retained nodes.
  # Actual placement is captured below instead of demanding new capacity there.
  if jq -e '.platform.transport.requires_rdma==true' "$model_config" >/dev/null; then
    jq -e '[.data["node-config-details"]["placement-configs"][]?["availability-domain"]]|unique|length==1' model-pool.json >/dev/null || model_fail 'RDMA reuse requires one actual availability domain; cross-AD RDMA placement is not inferred' || return
    compute_cluster=$(jq -r '.platform.allocation.compute_cluster_id // empty' "$model_config")
    jq -e --arg expected "$compute_cluster" '.data["node-config-details"]["compute-cluster-id"] | type=="string" and length>0 and ($expected=="" or .==$expected)' model-pool.json >/dev/null || model_fail 'RDMA pool lacks the required Compute Cluster binding' || return
  fi
  jq --arg pool "$pool" --slurpfile pool_info model-pool.json '.platform.allocation.gpu_pool_id=$pool | .platform.actual_availability_domains=([$pool_info[0].data["node-config-details"]["placement-configs"][]?["availability-domain"]]|unique) | .platform.allocation.compute_cluster_id=$pool_info[0].data["node-config-details"]["compute-cluster-id"]' "$model_config" > model-resolved-config.next.json
  mv model-resolved-config.next.json model-resolved-config.json
  model_config=model-resolved-config.json
}
model_workspace_ceiling() {
  [[ $(jq -r .storage.mode "$model_config") == direct_hf ]] || return 0
  # These are the already selected Ready full-GPU nodes, not another scan.
  # Allocatable is a scheduling ceiling; existing requests/usage remain unknown.
  jq -n --argjson replicas "$1" --argjson hosts "$HOSTS_PER_REPLICA" --argjson gpus "$GPUS_PER_POD" --slurpfile config "$model_config" --slurpfile nodes ready-pool-nodes.json '
    def quantity_bytes:
      (try (if type=="number" then . elif type=="string" then
        ([capture("^(?<number>[+]?(?:[0-9]+(?:[.][0-9]*)?|[.][0-9]+))(?<unit>[KMGTPE]i|[mkMGTPE]|[eE][+-]?[0-9]+)?$")][0]) as $q |
        if $q==null then null else ($q.unit//"") as $u | ($q.number|tonumber) *
          (if ($u|test("^[eE][+-]?[0-9]+$")) then pow(10;($u[1:]|tonumber))
           elif ($u|endswith("i")) then pow(1024;(["Ki","Mi","Gi","Ti","Pi","Ei"]|index($u))+1)
           else pow(1000;(["m","","k","M","G","T","P","E"]|index($u))-1) end)
        end else null end) catch null) | if type=="number" and isfinite and .>=0 then . else null end;
    ($config[0].storage.workspace_gib|tonumber) as $gib |
    if ($gib|isfinite) and $gib>0 then ($gib*1073741824|ceil) as $workspace |
      [$nodes[0][] | (.status.allocatable["ephemeral-storage"]//null) as $quantity | ($quantity|quantity_bytes) as $bytes |
        {node:(.metadata.name//.spec.providerID//"unnamed"),allocatable_quantity:$quantity,allocatable_bytes:$bytes,
         gpu_slots:(.status.allocatable["nvidia.com/gpu"]|tonumber/$gpus|floor),workspace_slots:(if $bytes==null then null else ($bytes/$workspace|floor) end)} |
        .maximum_pod_slots=(if .workspace_slots==null then 0 else [.gpu_slots,.workspace_slots]|min end)] as $capacity |
      {storage_mode:"direct_hf",workspace_gib:$gib,workspace_bytes:$workspace,checkpoint_download_bytes:$config[0].storage.snapshot_bytes,
       required_hosts_per_replica:$hosts,replicas_at_ceiling:$replicas,required_pod_slots:($replicas*$hosts),
       eligible_hosts:([$capacity[]|select(.maximum_pod_slots>0)]|length),maximum_pod_slots:([$capacity[].maximum_pod_slots]|add//0),
       unknown_quantity_nodes:[$capacity[]|select(.allocatable_bytes==null)|.node],nodes:$capacity,
       free_ephemeral_headroom:"unknown; existing requests and usage were not inspected",placement_validation:"upper_bound_only; Kubernetes requests and bounded rollout establish placement"} |
      .possible=((.unknown_quantity_nodes|length)==0 and .eligible_hosts>=$hosts and .maximum_pod_slots>=.required_pod_slots)
    else error("workspace_gib must be positive and finite") end
  ' > model-workspace-check.json || { model_fail 'Direct Hub workspace ceiling could not be evaluated; supply a positive measured workspace_gib and check selected node allocatable ephemeral-storage'; return 2; }
  jq . model-workspace-check.json
  jq -e .possible model-workspace-check.json >/dev/null || model_fail "Direct Hub per-Pod workspace $(jq -r .workspace_gib model-workspace-check.json)Gi cannot fit enough selected GPU-node slots, or allocatable ephemeral-storage is missing/unrecognized. For a custom/larger boot disk, grow its root partition/filesystem (oci-growfs) and wait for kubelet to report the increased allocatable storage before retrying; boot-volume size alone is not usable workspace. Verify the full checkpoint download requirement before reducing workspace_gib. This is an allocatable upper bound, not free-capacity evidence" || return
}
model_geometry() {
  local nodes gpus max_replicas selector key
  model_pool
  jq -e '.platform.allocation.gpu_pool_id | type=="string" and length>0' "$model_config" >/dev/null || model_fail 'GPU allocation is disabled or absent. Pipelines may be created before allocation, but model execution requires a retained GPU pool' || return
  nodes=$(jq -er .platform.node_count "$model_config")
  gpus=$(jq -er .platform.gpu_count_per_host "$model_config")
  max_replicas=$REPLICAS
  if jq -e .autoscaling.enabled "$model_config" >/dev/null; then
    for key in MIN_REPLICAS MAX_REPLICAS TARGET_INFLIGHT; do
      [[ ${!key:-} =~ ^[1-9][0-9]*$ ]] || model_fail "$key must be a positive integer" || return
    done
    (( MIN_REPLICAS <= REPLICAS && REPLICAS <= MAX_REPLICAS )) || model_fail 'Autoscaling bounds must contain the configured initial replica count' || return
    [[ $PROMETHEUS_URL =~ ^https?://[A-Za-z0-9_.:/-]+$ ]] || model_fail 'Use a non-secret reachable Prometheus URL' || return
    max_replicas=$MAX_REPLICAS
  fi
  (( GPUS_PER_POD <= gpus && max_replicas * HOSTS_PER_REPLICA <= nodes * (gpus / GPUS_PER_POD) && HOSTS_PER_REPLICA <= nodes )) || model_fail 'Requested replicas/hosts/GPUs exceed total model slots in the selected pool; choose a sufficient retained allocation' || return
  selector=$(jq -er .platform.gpu_selector "$model_config")
  [[ $selector == "oke-llm/allocation=$(jq -er .platform.platform_name "$model_config")" ]] || model_fail 'Unexpected allocation selector; model pipelines cannot retarget arbitrary GPU nodes' || return
  kubectl get nodes -l "$selector" -o json > allocation-nodes.json
  if [[ $(jq -r '.platform.binding_mode // "bound"' "$model_config") == runtime ]]; then
    jq --slurpfile pool model-pool.json '[.items[] | select((.spec.providerID // "" | split("/") | last) as $id | any($pool[0].data.nodes[]?;.id==$id and .["lifecycle-state"]=="ACTIVE"))]' allocation-nodes.json > pool-nodes.json
  else jq '.items' allocation-nodes.json > pool-nodes.json; fi
  jq --argjson gpus "$gpus" '[.[] | select(.spec.unschedulable!=true and any(.status.conditions[]?; .type=="Ready" and .status=="True")) |
    select((.metadata.labels["nvidia.com/gpu.sharing-strategy"] // "none")=="none" and (.metadata.labels["nvidia.com/mig.strategy"] // "none")=="none" and (.metadata.labels["nvidia.com/gpu.replicas"] // "1")=="1") |
    select((.status.allocatable["nvidia.com/gpu"] // "0" | tonumber)>=$gpus)]' pool-nodes.json > ready-pool-nodes.json
  jq -e --argjson nodes "$nodes" 'length>=$nodes' ready-pool-nodes.json >/dev/null || model_fail 'Selected OCI pool lacks the expected Ready schedulable full-GPU nodes; foreign pools, MIG/shared devices and missing devices do not count' || return
  model_workspace_ceiling "$max_replicas" || return
  if (( HOSTS_PER_REPLICA > 1 )); then
    local version minor
    version=$(jq -er .platform.kubernetes_version "$model_config")
    minor=${version#v1.}; minor=${minor%%.*}
    [[ $version == v1.* && $minor =~ ^[0-9]+$ ]] && (( minor >= 33 )) || model_fail 'Per-LWS-group host separation requires Kubernetes 1.33+ matchLabelKeys; use a supported cluster or another placement adapter' || return
    jq -e '.platform.required_components|index("lws")!=null' "$model_config" >/dev/null || model_fail 'Multi-node model requires the platform LWS controller' || return
  fi
  if jq -e '.platform.transport.requires_rdma==true' "$model_config" >/dev/null; then
    local resource
    resource=$(jq -er '.platform.transport.rdma_resource_name|select(type=="string" and length>0)' "$model_config") || model_fail 'RDMA transport has no validated device resource name' || return
    jq -e --arg resource "$resource" --argjson nodes "$nodes" '[.[]|select((.status.allocatable[$resource]//"0"|tonumber)>0)]|length>=$nodes' ready-pool-nodes.json >/dev/null || model_fail 'Expected RDMA resource is absent on required GPU hosts' || return
  fi
  jq -n --arg pool "$(jq -er .platform.allocation.gpu_pool_id "$model_config")" --argjson nodes "$nodes" --argjson gpus "$gpus" --arg checked_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson actual_ads "$(jq -c '.platform.actual_availability_domains // []' "$model_config")" --arg assessed_ad "$(jq -r '.platform.availability_domain // empty' "$model_config")" \
    '{actual_availability_domains:$actual_ads,discovery_assessed_ad:$assessed_ad,retained_pool_requires_new_regional_capacity:false,pool_id:$pool,checked_at:$checked_at,required_ready_nodes:$nodes,total_allocatable_gpus_per_host:$gpus,free_gpu_headroom:"unknown_other_namespace_requests_not_visible",placement_validation:"pending_bounded_kubernetes_rollout; capacity_is_not_reserved"}' > model-allocation-check.json
  echo 'Selected pool total GPU geometry is sufficient; free GPU headroom is unknown. Kubernetes requests and bounded rollout establish actual placement.'
}
model_platform_ready() {
  local entry name component_namespace mode expected deployment platform platform_owner context_name runtime_mode crd
  runtime_mode=$(jq -r '.platform.binding_mode // "bound"' "$model_config")
  if [[ $runtime_mode == runtime ]]; then
    platform=$(jq -er .platform.platform_name "$model_config")
    platform_owner=$(printf '%s' "$platform/$cluster" | sha256sum | cut -c1-32)
    context_name="oke-llm-model-context-$(printf '%s' "$namespace" | sha256sum | cut -c1-12)"
    kubectl -n kube-system get configmap "$context_name" -o json > platform-context-map.json || { model_fail "No trusted runtime context is accessible. Run $platform-model-onboarding for this exact model project/namespace and pipeline IDs"; return 2; }
    jq -e --arg owner "$platform_owner" --arg ns "$namespace" --arg project "$(jq -er .platform.project_id "$model_config")" '.metadata.labels["oke-llm/platform-owner"]==$owner and .metadata.annotations["oke-llm/model-namespace"]==$ns and .metadata.annotations["oke-llm/model-project-id"]==$project' platform-context-map.json >/dev/null || model_fail 'Missing trusted platform onboarding context for this exact model project/namespace' || return
    jq -er '.data["context.json"]|fromjson' platform-context-map.json > platform-context.json
    jq -e --arg platform "$platform" --arg cluster "$cluster" --arg ns "$namespace" --arg project "$(jq -er .platform.project_id "$model_config")" --arg pool "$(jq -r '.defaults.MODEL_GPU_POOL_ID // "runtime"' "$model_config")" '.platform_name==$platform and .cluster_id==$cluster and .model_namespace==$ns and .model_project_id==$project and .gpu_pool_id==$pool and (.components|type=="object")' platform-context.json >/dev/null || model_fail 'Trusted platform context targets another model boundary' || return
    jq --slurpfile context platform-context.json '.platform.components=$context[0].components' "$model_config" > platform-resolved-config.next.json
    mv platform-resolved-config.next.json platform-resolved-config.json
    model_config=platform-resolved-config.json
  fi
  jq -e '.platform.components|type=="object"' "$model_config" >/dev/null || model_fail 'No shared controller descriptors; run trusted platform onboarding after controller installation' || return
  jq -e '.platform as $p | all(($p.required_components//[])[]; $p.components[.]!=null)' "$model_config" >/dev/null || model_fail 'A required shared controller was not configured in this platform; update infrastructure and rerun trusted onboarding' || return
  echo '[]' > platform-readiness.json
  while IFS= read -r entry; do
    name=$(jq -er .key <<< "$entry")
    mode=$(jq -er .value.mode <<< "$entry")
    [[ $mode != retire ]] || model_fail "Required platform component $name is being retired" || return
    component_namespace=$(jq -er .value.namespace <<< "$entry")
    if [[ $mode == managed ]]; then
      kubectl -n "$component_namespace" get configmap "$(jq -er .value.owner_name <<< "$entry")" -o json > platform-owner.json || { model_fail "Required shared component $name has no accessible managed readiness marker; deploy/validate it and rerun trusted onboarding if its identity changed"; return 2; }
      if [[ $runtime_mode == runtime ]]; then
        expected=$(jq -er .value.ownership_token <<< "$entry")
        jq -e --arg owner "$expected" '.data.ownership_token==$owner and .data.status=="ready" and (.data.generation|type=="string" and length>0) and (.data.chart_version|type=="string" and length>0) and (.data.helm_revision|tonumber)>0' platform-owner.json >/dev/null || model_fail "Platform component $name has no current managed ready evidence with correct ownership" || return
      else
        expected=$(jq -er .value.generation <<< "$entry")
        jq -e --arg generation "$expected" '.data.generation==$generation and .data.status=="ready"' platform-owner.json >/dev/null || model_fail "Platform component $name is not ready at its bound generation" || return
      fi
    fi
    while IFS= read -r deployment; do
      kubectl -n "$component_namespace" get deployment "$deployment" -o json > platform-controller.json
      jq -e '(.spec.replicas//1)>0 and .status.observedGeneration>=.metadata.generation and (.status.availableReplicas//0)>=(.spec.replicas//1) and any(.status.conditions[]?; .type=="Available" and .status=="True")' platform-controller.json >/dev/null || model_fail "Platform controller $name/$deployment is unavailable or has an unobserved update" || return
      if [[ $runtime_mode == runtime && $mode == managed ]]; then
        local release_name
        release_name=$(jq -er .value.release_name <<< "$entry")
        jq -e --arg release "$release_name" --arg ns "$component_namespace" '.metadata.annotations["meta.helm.sh/release-name"]==$release and .metadata.annotations["meta.helm.sh/release-namespace"]==$ns' platform-controller.json >/dev/null || model_fail "Platform controller $name/$deployment does not belong to the trusted shared Helm release" || return
      fi
    done < <(jq -r '.value.deployment_names[]' <<< "$entry")
    while IFS= read -r crd; do
      kubectl get crd "$crd" -o json | jq -e 'any(.status.conditions[]?;.type=="Established" and .status=="True")' >/dev/null || model_fail "Required $name CRD is not Established: $crd" || return
    done < <(jq -r '.value.crd_names[]?' <<< "$entry")
    jq --arg name "$name" --arg mode "$mode" --arg checked_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg generation "$(if [[ $mode == managed ]]; then jq -r .data.generation platform-owner.json; fi)" '.+[{component:$name,mode:$mode,current_ready_generation:$generation,checked_at:$checked_at,controller_status:"observed_available"}]' platform-readiness.json > platform-readiness-next.json
    mv platform-readiness-next.json platform-readiness.json
  done < <(jq -c '.platform as $p | $p.components|to_entries[]|select(.key as $key | ($p.required_components//[])|index($key)!=null)' "$model_config")
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
    if [[ -s model-pool.json ]]; then
      nodes=$(jq -er --argjson minimum "$nodes" '[$minimum, (.data["node-config-details"].size // 0), (.data.nodes // [] | length)] | max' model-pool.json)
    fi
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
  if jq -e .autoscaling.enabled "$model_config" >/dev/null; then
    kubectl -n "$namespace" wait --for=condition=Ready "scaledobject/$release" --timeout="${timeout}s" || { model_fail 'KEDA ScaledObject is not Ready; validate the configured Prometheus endpoint/query and retained-allocation scaling bounds'; return 2; }
  fi
  if (( HOSTS_PER_REPLICA > 1 )); then
    kubectl -n "$namespace" wait --for=condition=Available "leaderworkerset/$release" --timeout="${timeout}s"
    kubectl -n "$namespace" wait --for=condition=Progressing=false "leaderworkerset/$release" --timeout="${timeout}s"
  fi
  if ! kubectl -n "$namespace" wait --for=condition=Ready pod -l "oke-llm/model=$identity" --timeout="${timeout}s"; then
    kubectl -n "$namespace" get pods -l "oke-llm/model=$identity" -o json > model-unscheduled-pods.json || true
    model_fail 'Bounded model readiness failed. Pool allocatable GPUs are not proof of free devices: inspect namespace Pod scheduling conditions, quota, image/model download and GPU availability before retrying'
    return 2
  fi
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
    '{status:"ready",model:$model,model_revision:$revision,model_revision_kind:(if $revision=="main" then "mutable_ref" else "immutable_commit" end),image:$image,checks:["pod_readiness","image_identity","health","model_identity"],inference_probe:($probe|if .=="none" then "not_run; choose a task-specific probe" else . end),responses_conversation_persistence:false}' > model-validation.json
  if jq -e '.lmcache.enabled // false' "$model_config" >/dev/null; then
    jq -e '[.items[] | select(.metadata.deletionTimestamp==null) | .spec.containers[] | select(.name=="vllm") | .command == ["bash","/lmcache/launch.sh"]] | length>0 and all(.[]; . == true)' model-pods.json >/dev/null || model_fail 'LMCache launcher is absent from a serving Pod' || return
    jq --slurpfile config "$model_config" '. + {lmcache:($config[0].lmcache + {store_retrieve_validation:"manual_cache_benchmark_required"}),routing:$config[0].routing_mode}' model-validation.json > model-validation-cache.json
    mv model-validation-cache.json model-validation.json
  fi
  kill "$model_forward_pid" 2>/dev/null || true
  wait "$model_forward_pid" 2>/dev/null || true
  trap - EXIT
}
