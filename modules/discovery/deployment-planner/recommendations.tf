# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  recommendation_policy = {
    id          = "hardware_fit_then_confirmed_growth_v1"
    description = "Recommendations prefer more memory per GPU, fewer GPUs and hosts per replica, and RDMA-capable hardware, then more additional complete replicas supportable by capacity AND entitlement in the selected AD. Exact-shape regional physical supply and fewer allocated GPUs break later ties. This is a hardware-fit/growth heuristic, not a throughput or cost prediction; supply and shared limits are not future reservations."
  }
  recommendation_inputs = { for option in concat(local.candidates, local.suggestions) : option.id => {
    gpu_memory_bytes  = try(local.catalog[option.gpu_shape].memory_bytes_per_gpu, 0)
    gpus_per_replica  = option.tensor_parallel_size * option.pipeline_parallel_size
    hosts_per_replica = try(option.hosts_per_replica, option.pipeline_parallel_size)
    rdma_capable = try(local.catalog[option.gpu_shape].rdma && anytrue([
      for row in local.shape_rows : row.shape.rdma_ports > 0 if row.region == option.region && row.ad == option.availability_domain && row.shape.shape == option.gpu_shape
    ]), false)
    ad_usable_hosts = min(option.available_instances, try(coalesce(try(option.entitled_instances, null), one([
      for row in local.availability_observations : row.entitled_instances if row.region == option.region && row.availability_domain == option.availability_domain && row.shape == option.gpu_shape
    ])), 0))
    # Sum physical supply for this exact shape once per AD; never add quota ceilings.
    regional_known_hosts = sum(concat([0], [for ad in distinct([for row in local.shape_rows : row.ad if row.region == option.region && row.shape.shape == option.gpu_shape]) : try(one(distinct([
      for row in local.shape_rows : row.capacity.available_instances if row.region == option.region && row.ad == ad && row.shape.shape == option.gpu_shape && try(row.capacity.availability_status == "AVAILABLE" && row.capacity.available_instances > 0, false) && try(row.capacity.fault_domain == null, true)
    ])), 0)]))
    node_count = option.node_count, replicas = option.replicas, allocated_gpus = option.node_count * option.gpus_per_node
  } }
  recommendation_metrics = { for id, input in local.recommendation_inputs : id => merge(input, {
    ad_max_replicas        = floor(input.ad_usable_hosts / input.node_count) * input.replicas
    ad_additional_replicas = max(0, floor(input.ad_usable_hosts / input.node_count) - 1) * input.replicas
  }) }
  rank_max_memory = max(concat([0], [for value in values(local.recommendation_metrics) : value.gpu_memory_bytes])...)
  rank_max_growth = max(concat([0], [for value in values(local.recommendation_metrics) : value.ad_additional_replicas])...)
  rank_max_supply = max(concat([0], [for value in values(local.recommendation_metrics) : value.regional_known_hosts])...)
  recommendation_keys = { for id, value in local.recommendation_metrics : id => format("%020.0f-%06d-%04d-%d-%012d-%012d-%08d-%04d-%s",
    local.rank_max_memory - value.gpu_memory_bytes, value.gpus_per_replica, value.hosts_per_replica, value.rdma_capable ? 0 : 1,
    local.rank_max_growth - value.ad_additional_replicas, local.rank_max_supply - value.regional_known_hosts,
    value.allocated_gpus, value.node_count, id
  ) }
  candidate_rank_index  = { for option in local.candidates : local.recommendation_keys[option.id] => merge(option, { recommendation = local.recommendation_metrics[option.id] }) }
  ranked_candidates     = [for key in sort(keys(local.candidate_rank_index)) : local.candidate_rank_index[key]]
  suggestion_rank_index = { for option in local.suggestions : local.recommendation_keys[option.id] => merge(option, { recommendation = local.recommendation_metrics[option.id] }) }
  ranked_suggestions    = [for key in sort(keys(local.suggestion_rank_index)) : local.suggestion_rank_index[key]]
}
