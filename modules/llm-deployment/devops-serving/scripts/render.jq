# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Input: validated deployment config. Output: Helm values and Kubernetes objects.
. as $c |
(if $c.requires_rdma and (($c.rdma_resource_name // "") | length)==0 then error("Resolve the existing cluster RDMA resource name before rendering.") else . end) |
def affinity:
  {nodeAffinity:{requiredDuringSchedulingIgnoredDuringExecution:{nodeSelectorTerms:[{matchExpressions:[{key:"oke-llm/allocation",operator:"In",values:[$c.name]}]}]}},
   podAntiAffinity:{requiredDuringSchedulingIgnoredDuringExecution:[{labelSelector:{matchLabels:{"oke-llm/model":$c.name,"oke-llm/specification":($c.specification_hash[:32])}},topologyKey:"kubernetes.io/hostname"}]}};
def resources:
  {requests:({cpu:"4",memory:"16Gi","nvidia.com/gpu":$c.tensor_parallel_size} + if $c.requires_rdma then {($c.rdma_resource_name):1} else {} end),limits:({"nvidia.com/gpu":$c.tensor_parallel_size} + if $c.requires_rdma then {($c.rdma_resource_name):1} else {} end)};
def gpu_tolerations: [{key:"nvidia.com/gpu",operator:"Exists",effect:"NoSchedule"}];
def network_annotations:
  if $c.requires_rdma and (($c.rdma_network_attachment // "") | length)>0 then {"k8s.v1.cni.cncf.io/networks":$c.rdma_network_attachment} else {} end;
def serving_env: [($c.engine_env // {}) | to_entries[] | {name:.key,value:(.value|tostring)}];
def vllm_args:
  ["serve",$c.model,"--revision",$c.model_revision,"--served-model-name","model","--host","0.0.0.0","--port","8000","--tensor-parallel-size",($c.tensor_parallel_size|tostring),"--pipeline-parallel-size",($c.pipeline_parallel_size|tostring),"--max-model-len",($c.context_length|tostring),"--max-num-seqs",($c.concurrency|tostring),"--dtype",$c.kv_dtype,"--kv-cache-dtype","auto","--gpu-memory-utilization","0.9","--distributed-executor-backend","mp"] +
  (if $c.serving_configuration == null then ["--default-chat-template-kwargs","{\"enable_thinking\":false}"] else [] end) + ($c.engine_args // []);

def container($leader):
  {name:"vllm",image:$c.engine_image,command:["vllm"],args:(vllm_args + ["--nnodes","$(LWS_GROUP_SIZE)","--node-rank","$(LWS_WORKER_INDEX)","--master-addr","$(LWS_LEADER_ADDRESS)"] + if $leader then [] else ["--headless"] end),resources:resources,
   ports:[{name:"http",containerPort:8000},{name:"distributed",containerPort:29501}],
   env:([{name:"VLLM_HOST_IP",valueFrom:{fieldRef:{fieldPath:"status.podIP"}}},{name:"NCCL_DEBUG",value:"INFO"}] + serving_env),
   securityContext:{capabilities:{add:["IPC_LOCK"]}},
   volumeMounts:[{name:"shm",mountPath:"/dev/shm"}],
   startupProbe:({tcpSocket:{port:8000},periodSeconds:10,failureThreshold:180}),
   readinessProbe:({httpGet:{path:"/health",port:8000},periodSeconds:10})}
  | if $leader then . else del(.startupProbe,.readinessProbe) end;
def pod($leader):
  {metadata:{labels:{"oke-llm/model":$c.name,"oke-llm/specification":($c.specification_hash[:32]),role:(if $leader then "leader" else "worker" end)},annotations:network_annotations},spec:{tolerations:gpu_tolerations,affinity:affinity,containers:[container($leader)],volumes:[{name:"shm",emptyDir:{medium:"Memory",sizeLimit:"8Gi"}}]}};
($c.engine_image|split("@")) as $image |
($image[0]|sub(":[^/:]+$";"")) as $engine_repository |
(($image[0]|capture(":(?<tag>[^/:]+)$").tag)? // null) as $explicit_tag |
($c.components.production_stack.router_image|split("@")) as $router |
{
 helm_values:{
  servingEngineSpec:{enableEngine:($c.pipeline_parallel_size==1),strategy:{type:"Recreate"},startupProbe:{failureThreshold:180,periodSeconds:10},runtimeClassName:"",modelSpec:[{
    tolerations:gpu_tolerations,podAnnotations:network_annotations,
    name:"model",modelURL:$c.model,modelRevision:$c.model_revision,
    repository:$engine_repository,tag:(($explicit_tag // ((if $c.engine_version=="nightly" then "nightly" else "v"+$c.engine_version end)|gsub("[^A-Za-z0-9_.-]";"-")[0:128]))+"@"+$image[1]),
    replicaCount:$c.replicas,resources:resources,affinity:affinity,podLabels:{"oke-llm/model":$c.name,"oke-llm/specification":($c.specification_hash[:32])},runtimeClassName:"",
    command:["vllm"],args:vllm_args,env:serving_env,
    vllmConfig:{v1:"1",maxModelLen:$c.context_length,maxNumSeqs:$c.concurrency,tensorParallelSize:$c.tensor_parallel_size,dtype:"auto",extraArgs:["--served-model-name","model","--revision",$c.model_revision,"--default-chat-template-kwargs","{\"enable_thinking\":false}"]},
    extraVolumes:[],extraVolumeMounts:[]
  }]},
  routerSpec:{enableRouter:true,repository:($router[0]|split(":")[0]),tag:($router[0]|split(":")[1]+"@"+$router[1]),serviceType:"ClusterIP",serviceDiscovery:(if $c.pipeline_parallel_size==1 then "k8s" else "static" end),
    staticBackends:([range(0;$c.replicas)|"http://"+$c.name+"-leader-"+tostring+":8000"]|join(",")),staticModels:([range(0;$c.replicas)|"model"]|join(",")),routingLogic:"roundrobin",
    nodeSelectorTerms:[{matchExpressions:[{key:"oke-llm/control",operator:"In",values:[$c.name]}]}]},
  cacheserverSpec:{enabled:false},"kube-prometheus-stack":{enabled:false},"prometheus-adapter":{enabled:false},"k8s-aibom":{enabled:false}
 },
 multi_node_manifest:{apiVersion:"v1",kind:"List",items:(if $c.pipeline_parallel_size>1 then
  [{apiVersion:"leaderworkerset.x-k8s.io/v1",kind:"LeaderWorkerSet",metadata:{name:$c.name,namespace:$c.namespace},spec:{replicas:$c.replicas,leaderWorkerTemplate:{size:$c.pipeline_parallel_size,restartPolicy:"RecreateGroupOnPodRestart",leaderTemplate:pod(true),workerTemplate:pod(false)}}}] +
  [range(0;$c.replicas)|{apiVersion:"v1",kind:"Service",metadata:{name:($c.name+"-leader-"+tostring),namespace:$c.namespace},spec:{selector:{"leaderworkerset.sigs.k8s.io/name":$c.name,"leaderworkerset.sigs.k8s.io/group-index":tostring,role:"leader"},ports:[{port:8000,targetPort:8000}]}}]
  else [] end)},
 benchmark_job:{apiVersion:"batch/v1",kind:"Job",metadata:{name:$c.job_name,namespace:$c.namespace},spec:{backoffLimit:0,activeDeadlineSeconds:3600,ttlSecondsAfterFinished:3600,template:{spec:{restartPolicy:"Never",nodeSelector:{"oke-llm/control":$c.name},containers:[{name:"benchmark",image:$c.components.benchmark_image,command:["bash","/benchmark/benchmark.sh"],args:[],resources:{requests:{cpu:"2",memory:"2Gi"},limits:{memory:"8Gi"}},volumeMounts:[{name:"benchmark",mountPath:"/benchmark",readOnly:true}]}],volumes:[{name:"benchmark",configMap:{name:$c.job_name}}]}}}}
}
