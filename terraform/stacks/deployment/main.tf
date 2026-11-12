# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12" } }
}
provider "oci" { region = var.region }
module "model_profile" {
  source         = "../../modules/model-profile"
  model          = var.model
  revision       = var.model_revision
  context_length = var.context_length
  concurrency    = var.concurrency
  kv_dtype       = var.kv_dtype
  runtime_gib    = var.runtime_gib
  margin         = var.margin
}
locals {
  engines       = jsondecode(file("${path.module}/../../../catalogs/engines.json")).engines
  engine        = jsondecode(var.serving_configuration != null ? jsonencode(var.serving_configuration.engine) : jsonencode(try([for engine in local.engines : engine if engine.image == var.engine_image && engine.version == var.engine_version][0], local.engines[0])))
  engine_args   = var.engine_args != null ? var.engine_args : try(tolist(var.serving_configuration.recipe.args), [])
  engine_env    = var.engine_env != null ? var.engine_env : try(tomap(var.serving_configuration.recipe.env), {})
  managed_flags = ["--model", "--revision", "--served-model-name", "--host", "--port", "--tensor-parallel-size", "-tp", "--pipeline-parallel-size", "-pp", "--max-model-len", "--max-num-seqs", "--dtype", "--kv-cache-dtype", "--gpu-memory-utilization", "--distributed-executor-backend", "--nnodes", "--node-rank", "--master-addr", "--headless"]
  gpu           = try(jsondecode(file("${path.module}/../../../catalogs/gpus.json")).shapes[var.gpu_shape], null)
  profile       = module.model_profile.profile
  a             = local.profile.architecture.attention
  tp            = var.tensor_parallel_size
  pp            = var.pipeline_parallel_size
  rank_bytes = try(ceil((
    local.profile.memory.weight_bytes / local.tp * min(local.a.layers, ceil(local.a.layers / local.pp) + (local.pp > 1 ? 1 : 0)) / local.a.layers +
    (local.tp * local.pp == 1 ? 0 : 2 * local.a.vocab_size * local.a.hidden_size * max([for dtype in keys(local.profile.weights.elements_by_dtype) : lookup({ F64 = 8, F32 = 4, F16 = 2, BF16 = 2 }, dtype, 8)]...) * (var.kv_dtype == "float32" ? 2 : 1)) +
    local.profile.memory.kv_bytes * min(local.a.layers, ceil(local.a.layers / local.pp) + (local.pp > 1 ? 1 : 0)) / local.a.layers * max(1, ceil(local.a.kv_heads / local.tp)) / local.a.kv_heads + local.profile.memory.runtime_allowance_bytes
  ) * (1 + local.profile.memory.assumptions.safety_margin_fraction)), null)
}
module "engine_check" {
  source  = "../../modules/deployment-planner"
  profile = local.profile
  regions = []
  engines = [local.engine]
}
resource "terraform_data" "specification" {
  input = { model_sha = var.model_revision, image = var.engine_image, tp = local.tp, pp = local.pp, node_count = var.node_count, serving_configuration = var.serving_configuration, expert_configuration = var.expert_configuration, expert_rank_memory_gib = var.expert_rank_memory_gib, engine_args = local.engine_args, engine_env = local.engine_env }

  lifecycle {
    precondition {
      condition     = try(local.profile.model.chat_template_available && local.profile.model.pipeline_tag == "text-generation", false) && local.engine.image == var.engine_image && local.engine.version == var.engine_version && (var.expert_configuration || alltrue([for check in module.engine_check.assessment.engine_checks : check.architecture_supported && check.version_hints_satisfied]))
      error_message = "Selected image/version must match the frozen discovery configuration or legacy catalog. Unsupported engine evidence requires explicit expert configuration."
    }
    precondition {
      condition = try(
        local.profile.model.resolved_revision == var.model_revision &&
        (var.expert_configuration && var.expert_rank_memory_gib != null ? var.expert_rank_memory_gib * pow(1024, 3) : local.rank_bytes) > 0 &&
        (var.expert_configuration && var.expert_rank_memory_gib != null ? var.expert_rank_memory_gib * pow(1024, 3) : local.rank_bytes) <= local.gpu.memory_bytes_per_gpu * 0.9 &&
      ((local.profile.memory.status == "estimated" && contains(local.engine.gpu_compute_capabilities, local.gpu.compute_capability)) || (var.expert_configuration && var.expert_rank_memory_gib != null && local.gpu.compute_capability >= 75)), false)
      error_message = "Per-rank GPU memory must fit. Unsupported estimation requires an explicit expert rank-memory bound; aggregate sizing is not a per-rank proof."
    }
    precondition {
      condition = try(contains([1, 2, 4, 8], local.tp) && local.tp <= local.gpu.gpus && local.pp >= 1 && floor(local.pp) == local.pp && var.replicas >= 1 && floor(var.replicas) == var.replicas && var.node_count == local.pp * var.replicas &&
        (var.expert_configuration || (local.pp <= local.a.layers && local.a.heads % local.tp == 0 && (local.a.kv_heads % local.tp == 0 || local.tp % local.a.kv_heads == 0))) &&
      (local.pp == 1 || local.engine.multi_node_backend == "mp") && (!var.requires_rdma || (local.gpu.compute_cluster_supported && contains(jsondecode(file("${path.module}/../../../catalogs/gpus.json")).compute_cluster_regions, var.region))), false)
      error_message = "TP must fit the GPU host, PP/replicas must match node count, and RDMA must be supported. Expert mode does not bypass allocation geometry."
    }
    precondition {
      condition = var.serving_configuration == null ? true : try(
        var.serving_configuration.model.resolved_revision == var.model_revision && var.serving_configuration.model.repository == var.model &&
        local.engine.platform == "linux/${local.gpu.cpu_architecture}" &&
      (var.expert_configuration || var.serving_configuration.status == "resolved_requires_validation"), false)
      error_message = "Frozen configuration must match the model revision and GPU node CPU platform. Unresolved recipe settings need explicit expert configuration."
    }
    precondition {
      condition = var.serving_configuration == null || var.expert_configuration ? true : try(
        var.serving_configuration.recipe.hardware[local.gpu.recipe_hardware] == "verified" &&
        var.serving_configuration.recipe.selected_hardware == local.gpu.recipe_hardware &&
        contains(var.serving_configuration.recipe.compatible_strategies, "single_node_tp") && local.pp == 1 &&
      local.tp == coalesce(try(tonumber(var.serving_configuration.recipe.variant_metadata.tp), null), try(tonumber(var.serving_configuration.recipe.strategy_overrides.single_node_tp.tp), null), try(tonumber(var.serving_configuration.recipe.strategy_overrides.single_node_tp.tp[local.gpu.recipe_hardware]), null)), false)
      error_message = "No matching tested recipe configuration for this GPU/TP/PP. Supply an explicit expert configuration; hardware similarity alone is not validation."
    }
    precondition {
      condition     = alltrue([for a in local.engine_args : !contains(local.managed_flags, split("=", a)[0])]) && alltrue([for k, v in local.engine_env : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", k)) && !contains(["VLLM_HOST_IP", "LWS_GROUP_SIZE", "LWS_WORKER_INDEX", "LWS_LEADER_ADDRESS"], k)])
      error_message = "Serving argv/env cannot override managed identity, topology or reserved distributed settings; use dedicated deployment variables."
    }
    precondition {
      condition     = try(var.boot_volume_gib * pow(1024, 3) >= local.profile.weights.tensor_data_bytes * 1.3 + 50 * pow(1024, 3), false)
      error_message = "Boot volume must allow the complete checkpoint cache plus image/OS headroom on every worker."
    }
  }
}
module "allocation" {
  source              = "../../modules/gpu-allocation"
  tenancy_ocid        = var.tenancy_ocid
  compartment_id      = var.compartment_id
  cluster_id          = var.cluster_id
  region              = var.region
  availability_domain = var.availability_domain
  subnet_id           = var.subnet_id
  gpu_image_id        = var.gpu_image_id
  cpu_image_id        = var.cpu_image_id
  cpu_subnet_id       = var.cpu_subnet_id
  cpu_node_count      = var.cpu_node_count
  gpu_shape           = var.gpu_shape
  node_count          = var.node_count
  requires_rdma       = var.requires_rdma
  name                = var.name
  observation_id      = var.observation_id
  boot_volume_gib     = var.boot_volume_gib
  pod_subnet_id       = var.pod_subnet_id
  specification_id    = terraform_data.specification.id
}
module "delivery" {
  source         = "../../modules/devops-serving"
  tenancy_ocid   = var.tenancy_ocid
  compartment_id = var.compartment_id
  subnet_id      = var.devops_subnet_id
  name           = var.name
  config = {
    name                  = var.name, namespace = var.name, cluster_id = var.cluster_id, cluster_compartment_id = module.allocation.allocation.cluster_compartment_id, region = var.region
    model                 = var.model, model_revision = var.model_revision, engine_image = var.engine_image, engine_version = var.engine_version
    node_count            = var.node_count, gpu_shape = var.gpu_shape, tensor_parallel_size = local.tp, pipeline_parallel_size = local.pp, replicas = var.replicas
    context_length        = var.context_length, concurrency = var.concurrency, kv_dtype = var.kv_dtype, requires_rdma = var.requires_rdma
    kubernetes_version    = module.allocation.allocation.kubernetes_version, assessment_id = var.assessment_id
    serving_configuration = var.serving_configuration, expert_configuration = var.expert_configuration
    engine_args           = local.engine_args, engine_env = local.engine_env, expert_rank_memory_gib = var.expert_rank_memory_gib
    install_gpu_operator  = var.install_gpu_operator
    benchmark_requests    = var.benchmark_requests, benchmark_input_tokens = var.benchmark_input_tokens, benchmark_output_tokens = var.benchmark_output_tokens
  }
  depends_on = [module.allocation]
}
output "allocation" { value = module.allocation.allocation }
output "delivery" { value = module.delivery.delivery }
output "bootstrap_rbac" { value = module.delivery.delivery.bootstrap_rbac }
