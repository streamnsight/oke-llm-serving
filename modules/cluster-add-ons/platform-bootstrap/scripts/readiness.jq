# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Readiness checks advertised capacity only, not free GPUs or CUDA/NCCL operation.
.config as $c |
($c.gpu_allocation_enabled != false) as $check_gpu |
def schedulable: (.spec.unschedulable!=true and any(.status.conditions[]?; .type=="Ready" and .status=="True"));
def gpu_node:
 (.metadata.labels // {}) as $labels |
 any(["nvidia.com/gpu", "nvidia.com/gpu.present", "oci.oraclecloud.com/gpu-shape", "feature.node.kubernetes.io/pci-10de.present"][]; $labels[.]=="true") or
 any(((.status.capacity // {}) + (.status.allocatable // {})) | to_entries[]; (.key|test("^(nvidia.com/(gpu|mig-)|amd.com/gpu|intel.com/gpu)")) and ((.value|tonumber)>0)) or
 (($labels["node.kubernetes.io/instance-type"] // "") | contains("GPU"));
[.gpu_nodes.items[]? | select(schedulable) | select(((.status.allocatable["nvidia.com/gpu"] // "0")|tonumber)>=$c.gpu_count_per_host)] as $gpus |
[.cpu_nodes.items[]? | select(schedulable) |
 select((.metadata.labels["node.kubernetes.io/instance-type"] // "") as $shape | $shape!="" and ($shape|contains("GPU")|not)) |
 select(gpu_node|not) |
 select(all(.spec.taints[]?; .effect!="NoSchedule" and .effect!="NoExecute"))] as $cpus |
(($c.rdma_resource_name // "") | if length==0 then null else . end) as $requested |
([$gpus[].status.allocatable | to_entries[] | select(.key|test("^(rdma/|nvidia\\.com/.*(rdma|roce))";"i")) | select((.value|tonumber)>=1) | .key] | unique |
 map(. as $key | select([$gpus[] | select(((.status.allocatable[$key] // "0")|tonumber)>=1)] | length >= $c.node_count))) as $candidates |
(if $check_gpu and $c.requires_rdma then ($requested // (if ($candidates|length)==1 then $candidates[0] else null end)) else null end) as $resource |
(if $resource==null then 0 else ([$gpus[] | select(((.status.allocatable[$resource] // "0")|tonumber)>=1)] | length) end) as $rdma_nodes |
{
  ready:((if $check_gpu then ($gpus|length)>=$c.node_count else true end) and (if ($c.enable_lws or $c.cpu_components_required) then ($cpus|length)>=1 else true end) and (if $check_gpu and $c.requires_rdma then $resource!=null and $rdma_nodes>=$c.node_count else true end)),
  fatal:($check_gpu and $c.requires_rdma and $requested==null and ($candidates|length)>1),
  validation_scope:(if $check_gpu then "platform_and_gpu_capacity" else "cpu_components_only" end),
  gpu_validation:(if $check_gpu then "advertised_capacity_only" else "skipped_debug" end),
  gpu_ready_nodes:($gpus|length), cpu_ready_nodes:($cpus|length), cpu_shapes:([$cpus[].metadata.labels["node.kubernetes.io/instance-type"]]|unique), rdma_ready_nodes:$rdma_nodes, rdma_resource_name:$resource,
  reasons:[
    (if $check_gpu and ($gpus|length)<$c.node_count then "Insufficient Ready, schedulable GPU hosts advertising the full shape GPU count. Enable/configure the OKE GPU add-on and supported image." else empty end),
    (if ($c.enable_lws or $c.cpu_components_required) and ($cpus|length)<1 then "No Ready, schedulable existing CPU node without blocking taints. No CPU pool will be created." else empty end),
    (if $check_gpu and $c.requires_rdma and ($resource==null or $rdma_nodes<$c.node_count) then "No unique RDMA resource on enough GPU hosts. Configure the OKE network add-on, or specify the existing RDMA resource." else empty end)
  ]
}
