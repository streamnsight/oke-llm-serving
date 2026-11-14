# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Input: {config, nodes: Kubernetes NodeList}. Read only; never installs plugins.
.config as $c |
[.nodes.items[]? | select(any(.status.conditions[]?; .type=="Ready" and .status=="True")) |
 select(((.status.allocatable["nvidia.com/gpu"] // "0")|tonumber) >= $c.tensor_parallel_size)] as $gpu_nodes |
(($c.rdma_resource_name // "") | if length==0 then null else . end) as $requested |
([ $gpu_nodes[].status.allocatable | to_entries[] |
   select(.key|test("^(rdma/|nvidia\\.com/.*(rdma|roce))";"i")) |
   select((.value|tonumber)>=1) | .key ] | unique |
 map(. as $key | select([$gpu_nodes[] | select(((.status.allocatable[$key] // "0")|tonumber)>=1)] | length >= $c.node_count))) as $candidates |
(if $c.requires_rdma then ($requested // (if ($candidates|length)==1 then $candidates[0] else null end)) else null end) as $resource |
(if $resource==null then 0 else ([$gpu_nodes[] | select(((.status.allocatable[$resource] // "0")|tonumber)>=1)] | length) end) as $rdma_nodes |
{
  ready: (($gpu_nodes|length)>=$c.node_count and (if $c.requires_rdma then $resource!=null and $rdma_nodes>=$c.node_count else true end)),
  fatal:($c.requires_rdma and $requested==null and ($candidates|length)>1),
  rdma_resource_name:$resource, gpu_ready_nodes:($gpu_nodes|length), rdma_ready_nodes:$rdma_nodes,
  rdma_candidates:$candidates, ownership:"existing_cluster",
  reasons:([
    (if ($gpu_nodes|length)<$c.node_count then "Insufficient Ready nodes advertising the required nvidia.com/gpu count." else empty end),
    (if $c.requires_rdma and $resource==null then "No unique RDMA resource is advertised on enough GPU nodes. Configure the OKE network add-on or specify rdma_resource_name." else empty end),
    (if $c.requires_rdma and $resource!=null and $rdma_nodes<$c.node_count then "The selected RDMA resource is not allocatable on enough GPU nodes." else empty end)
  ])
}
