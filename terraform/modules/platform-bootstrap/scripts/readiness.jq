# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Readiness checks advertised capacity only, not free GPUs or CUDA/NCCL operation.
.config as $c |
def schedulable: (.spec.unschedulable!=true and any(.status.conditions[]?; .type=="Ready" and .status=="True"));
[.gpu_nodes.items[]? | select(schedulable) | select(((.status.allocatable["nvidia.com/gpu"] // "0")|tonumber)>=$c.gpu_count_per_host)] as $gpus |
[.cpu_nodes.items[]? | select(schedulable) |
 select((.metadata.labels["node.kubernetes.io/instance-type"] // "") as $shape | $shape!="" and ($shape|contains("GPU")|not)) |
 select(((.status.allocatable["nvidia.com/gpu"] // "0")|tonumber)==0) |
 select(all(.spec.taints[]?; .effect!="NoSchedule" and .effect!="NoExecute"))] as $cpus |
(($c.rdma_resource_name // "") | if length==0 then null else . end) as $requested |
([$gpus[].status.allocatable | to_entries[] | select(.key|test("^(rdma/|nvidia\\.com/.*(rdma|roce))";"i")) | select((.value|tonumber)>=1) | .key] | unique |
 map(. as $key | select([$gpus[] | select(((.status.allocatable[$key] // "0")|tonumber)>=1)] | length >= $c.node_count))) as $candidates |
(if $c.requires_rdma then ($requested // (if ($candidates|length)==1 then $candidates[0] else null end)) else null end) as $resource |
(if $resource==null then 0 else ([$gpus[] | select(((.status.allocatable[$resource] // "0")|tonumber)>=1)] | length) end) as $rdma_nodes |
{
  ready:(($gpus|length)>=$c.node_count and (if $c.enable_lws then ($cpus|length)>=1 else true end) and (if $c.requires_rdma then $resource!=null and $rdma_nodes>=$c.node_count else true end)),
  fatal:($c.requires_rdma and $requested==null and ($candidates|length)>1),
  gpu_ready_nodes:($gpus|length), cpu_ready_nodes:($cpus|length), rdma_ready_nodes:$rdma_nodes, rdma_resource_name:$resource,
  reasons:[
    (if ($gpus|length)<$c.node_count then "Insufficient Ready, schedulable GPU hosts advertising the full shape GPU count. Enable/configure the OKE GPU add-on and supported image." else empty end),
    (if $c.enable_lws and ($cpus|length)<1 then "No Ready, schedulable existing CPU node without blocking taints. No CPU pool will be created." else empty end),
    (if $c.requires_rdma and ($resource==null or $rdma_nodes<$c.node_count) then "No unique RDMA resource on enough GPU hosts. Configure the OKE network add-on, or specify the existing RDMA resource." else empty end)
  ]
}
