# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform { required_version = ">= 1.5.0" }

variable "profile" { type = any }
variable "options" { type = any }
variable "assessment" {
  type    = any
  default = {}
}
variable "serving_configuration" {
  type    = any
  default = {}
}

module "model_capabilities" {
  source  = "../../llm-deployment/cache-capabilities"
  profile = var.profile
  serving = var.serving_configuration
}
module "option_capabilities" {
  for_each               = var.options
  source                 = "../../llm-deployment/cache-capabilities"
  profile                = var.profile
  serving                = try(each.value.serving_configuration, var.serving_configuration)
  hosts_per_replica      = try(each.value.hosts_per_replica, each.value.pipeline_parallel_size, 1)
  pipeline_parallel_size = try(each.value.pipeline_parallel_size, 1)
}

locals {
  observations_by_scope = { for row in try(var.assessment.shape_observations, []) : jsonencode([row.region, row.availability_domain, row.shape]) => row... }
  observations          = { for id, option in var.options : id => lookup(local.observations_by_scope, jsonencode([option.region, option.availability_domain, option.gpu_shape]), []) }
  inputs = { for id, option in var.options : id => {
    tp             = try(option.tensor_parallel_size, 0)
    gpus_per_host  = try(option.gpus_per_node, 0)
    minimum_decode = try(coalesce(option.requested_minimum_replicas, 1), 1)
    available      = try(option.available_instances, null)
    # These counts are whole-host quantities established by the existing planner.
    # Never replace missing entitlement with physical capacity or a quota ceiling.
    entitled = try(coalesce(try(option.entitled_instances, null), one(distinct([
      for row in local.observations[id] : row.entitled_instances
      if try(row.limit_status == "positive" && row.headroom_status == "positive" && row.quota_mapping_complete && row.entitled_instances >= 0 && floor(row.entitled_instances) == row.entitled_instances, false)
    ]))), null)
    scoped_capacity = try(option.availability == "available_at_scan", false) && try(option.fault_domain == null, true) && alltrue([
      for row in local.observations[id] : try(row.capacity.fault_domain == null && row.capacity.availability_status == "AVAILABLE" && row.capacity_status == "positive", false)
    ])
    confirmed_entitlement = try(option.entitlement == "confirmed_for_quantity", true) && try(option.limit_status == "positive", true) && try(option.headroom_status == "positive", true)
    geometry_valid        = try(option.tensor_parallel_size > 0 && floor(option.tensor_parallel_size) == option.tensor_parallel_size && option.gpus_per_node >= option.tensor_parallel_size && floor(option.gpus_per_node) == option.gpus_per_node && coalesce(try(option.requested_minimum_replicas, null), 1) >= 1 && floor(coalesce(try(option.requested_minimum_replicas, null), 1)) == coalesce(try(option.requested_minimum_replicas, null), 1), false)
    slots                 = try(max(0, floor(option.gpus_per_node / option.tensor_parallel_size)), 0)
  } }
  # Each role holds a full model, sharded by TP inside one host. Preserve the
  # requested minimum decode replicas, then fill spare complete slots with decode.
  counts = { for id, input in local.inputs : id => {
    hosts  = ceil((1 + input.minimum_decode) / max(1, input.slots))
    decode = ceil((1 + input.minimum_decode) / max(1, input.slots)) * max(1, input.slots) - 1
  } }
  checks = { for id, input in local.inputs : id => {
    physical = try(input.available >= local.counts[id].hosts && floor(input.available) == input.available, false)
    quota    = try(input.entitled >= local.counts[id].hosts && floor(input.entitled) == input.entitled, false)
  } }
  reasons = { for id, input in local.inputs : id => compact(concat(module.option_capabilities[id].assessment.disaggregation.reasons, [
    input.geometry_valid ? "" : "P/D needs a valid positive TP size, GPU count per host and minimum decode replica count.",
    input.scoped_capacity ? "" : "Physical capacity is not confirmed for the exact selected AD and whole-host scope.",
    local.checks[id].physical ? "" : "P/D needs ${local.counts[id].hosts} whole hosts (${local.counts[id].hosts * input.gpus_per_host} allocated GPUs) in this AD; reported physical capacity does not confirm that quantity.",
    input.confirmed_entitlement && local.checks[id].quota ? "" : "P/D needs GPU headroom for ${local.counts[id].hosts} whole hosts (${local.counts[id].hosts * input.gpus_per_host} allocated GPUs) in this AD; quantity-specific entitlement does not confirm that allocation."
  ])) }
  aggregated = { for id, option in var.options : id => {
    serving_mode = "aggregated", prefill_replicas = 0, decode_replicas = try(option.replicas, null),
    allocation = {
      required_hosts             = option.node_count, gpus_per_host = try(option.gpus_per_node, null), allocated_gpus = try(option.node_count * option.gpus_per_node, null),
      required_gpus_per_replica  = try(option.tensor_parallel_size * option.pipeline_parallel_size, null),
      requested_minimum_replicas = try(option.requested_minimum_replicas, null), replicas = try(option.replicas, null),
      replicas_per_host          = try(option.replicas_per_node, null), unused_gpus = try(option.node_count * option.gpus_per_node - option.replicas * option.tensor_parallel_size * option.pipeline_parallel_size, null),
      tensor_parallel_size       = try(option.tensor_parallel_size, null), pipeline_parallel_size = try(option.pipeline_parallel_size, null)
    },
    infrastructure_variables = {}, model_variables = {}
  } }
  disaggregated = { for id, option in var.options : id => {
    serving_mode = "disaggregated", prefill_replicas = 1, decode_replicas = local.counts[id].decode,
    allocation = {
      required_hosts             = local.counts[id].hosts, gpus_per_host = local.inputs[id].gpus_per_host, allocated_gpus = local.counts[id].hosts * local.inputs[id].gpus_per_host,
      required_gpus_per_replica  = local.inputs[id].tp,
      requested_minimum_replicas = local.inputs[id].minimum_decode, replicas = local.counts[id].decode,
      replicas_per_host          = local.inputs[id].slots, unused_gpus = local.counts[id].hosts * local.inputs[id].gpus_per_host - (local.counts[id].decode + 1) * local.inputs[id].tp,
      tensor_parallel_size       = local.inputs[id].tp, pipeline_parallel_size = 1
    },
    infrastructure_variables = { node_count = local.counts[id].hosts },
    model_variables = {
      serving_mode = "disaggregated", prefill_replicas = 1, replicas = local.counts[id].decode,
      min_replicas = local.counts[id].decode, max_replicas = local.counts[id].decode,
      lmcache_mode = "disabled", routing_mode = "auto", api_frontend = "python", autoscaling_enabled = false, router_enabled = true
    }
  } if length(local.reasons[id]) == 0 }
  pd_status = length(local.disaggregated) > 0 ? "eligible_for_testing" : !module.model_capabilities.assessment.disaggregation.selectable ? module.model_capabilities.assessment.disaggregation.status : length(var.options) == 0 ? "no_confirmed_options" : anytrue([for capabilities in values(module.option_capabilities) : capabilities.assessment.disaggregation.selectable]) ? "capacity_not_confirmed_for_quantity" : "unsupported_by_adapter"
}

output "layouts" {
  value = {
    aggregated = {
      status  = length(local.aggregated) > 0 ? "available_at_scan" : "no_confirmed_options", reasons = [],
      options = local.aggregated, unavailable_options = {}
    },
    disaggregated = {
      status = local.pd_status,
      reasons = length(local.disaggregated) > 0 ? [] : distinct(concat(module.model_capabilities.assessment.disaggregation.reasons,
      flatten(values(local.reasons)), length(var.options) == 0 && module.model_capabilities.assessment.disaggregation.selectable ? ["No capacity-confirmed hardware options are available for P/D assessment."] : [])),
      options             = local.disaggregated,
      unavailable_options = { for id, reasons in local.reasons : id => { reasons = reasons, required_hosts = local.counts[id].hosts, allocated_gpus = local.counts[id].hosts * local.inputs[id].gpus_per_host } if length(reasons) > 0 }
    }
  }
}
