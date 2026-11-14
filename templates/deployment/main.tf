# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12" } }
}
provider "oci" { region = coalesce(var.region, local.region) }
data "oci_identity_tenancy" "target" { tenancy_id = var.tenancy_ocid }
data "oci_identity_regions" "available" {}
provider "oci" {
  alias  = "home"
  region = one([for region in data.oci_identity_regions.available.regions : region.name if region.key == data.oci_identity_tenancy.target.home_region_key])
}
module "control_plane" { source = "../../modules/control-plane-sizing" }
module "serving_runtime" {
  count  = var.provision_resources || var.inspect_serving_image ? 1 : 0
  source = "../../modules/serving-image-metadata"
  image  = local.engine_image
}
module "target" {
  source              = "../../modules/deployment-target"
  cluster_id          = var.cluster_id
  availability_domain = local.availability_domain
  gpu_shape           = local.gpu_shape
  gpu_architecture    = try(local.gpu.cpu_architecture, "amd64")
  requires_rdma       = local.requires_rdma
  cpu_shape           = local.cpu_requirements.shape
  os_version          = var.os_version
  worker_nsg_ids      = var.worker_nsg_ids
  pod_nsg_ids         = var.pod_nsg_ids
  devops_nsg_ids      = var.devops_nsg_ids
  overrides           = { for k, v in { gpu_image_id = var.gpu_image_id, cpu_image_id = var.cpu_image_id, subnet_id = var.subnet_id, cpu_subnet_id = var.cpu_subnet_id, devops_subnet_id = var.devops_subnet_id, pod_subnet_id = var.pod_subnet_id } : k => try(trimspace(v) != "" ? trimspace(v) : null, null) }
}
module "model_profile" {
  source         = "../../modules/model-profile"
  model          = local.model
  revision       = local.model_revision
  context_length = local.context_length
  concurrency    = local.concurrency
  kv_dtype       = local.kv_dtype
  runtime_gib    = local.runtime_gib
  margin         = local.margin
}
locals {
  engine               = local.resolved_engine
  engine_args          = var.engine_args != null ? var.engine_args : try(tolist(local.serving_configuration.recipe.args), [])
  engine_env           = var.engine_env != null ? var.engine_env : try(tomap(local.serving_configuration.recipe.env), {})
  managed_flags        = ["--model", "--revision", "--served-model-name", "--host", "--port", "--tensor-parallel-size", "-tp", "--pipeline-parallel-size", "-pp", "--max-model-len", "--max-num-seqs", "--dtype", "--kv-cache-dtype", "--gpu-memory-utilization", "--distributed-executor-backend", "--nnodes", "--node-rank", "--master-addr", "--headless"]
  gpu                  = try(jsondecode(file("${path.module}/../../modules/accelerator-inventory/data/gpus.json")).shapes[local.gpu_shape], null)
  profile              = module.model_profile.profile
  a                    = local.profile.architecture.attention
  selected_rank_budget = try(local.suggested ? local.selected.estimated_rank_bytes : null, null)
  rank_bytes = try(ceil((
    local.profile.memory.weight_bytes / local.tp * min(local.a.layers, ceil(local.a.layers / local.pp) + (local.pp > 1 ? 1 : 0)) / local.a.layers +
    (local.tp * local.pp == 1 ? 0 : 2 * local.a.vocab_size * local.a.hidden_size * max([for dtype in keys(local.profile.weights.elements_by_dtype) : lookup({ F64 = 8, F32 = 4, F16 = 2, BF16 = 2 }, dtype, 8)]...) * (local.kv_dtype == "float32" ? 2 : 1)) +
    local.profile.memory.kv_bytes * min(local.a.layers, ceil(local.a.layers / local.pp) + (local.pp > 1 ? 1 : 0)) / local.a.layers * max(1, ceil(local.a.kv_heads / local.tp)) / local.a.kv_heads + local.profile.memory.runtime_allowance_bytes
  ) * (1 + local.profile.memory.assumptions.safety_margin_fraction)), null)
}
module "engine_check" {
  source  = "../../modules/deployment-planner"
  profile = local.profile
  regions = []
}
resource "terraform_data" "specification" {
  input = { model_sha = local.model_revision, image = local.engine_image, tp = local.tp, pp = local.pp, node_count = local.node_count, serving_configuration = local.serving_configuration, expert_configuration = var.expert_configuration, expert_rank_memory_gib = var.expert_rank_memory_gib, engine_args = local.engine_args, engine_env = local.engine_env }

  lifecycle {
    precondition {
      condition     = var.region == null || local.region == null || var.region == local.region
      error_message = "The RMS/CLI region must match the selected discovery region. Create the deployment stack in that region so the cluster picker and regional images match."
    }
    precondition {
      condition     = length(compact([var.discovery != null ? "object" : "", local.inline_json != null ? "inline" : "", local.object_uri != null ? "storage" : ""])) <= 1
      error_message = "Use only one discovery transport: local object, compact inline JSON or Object Storage."
    }
    precondition {
      condition     = !var.provision_resources || module.target.target.ready
      error_message = "Resolve all deployment_preview.target.issues before enabling resource creation."
    }
    precondition {
      condition     = try(trimspace(var.network_vcn_id), "") == "" || var.network_vcn_id == module.target.target.vcn_id
      error_message = "The network VCN filter must match the selected OKE cluster's VCN."
    }
    precondition {
      condition     = local.benchmark_input_tokens > 0 && local.benchmark_input_tokens + local.benchmark_output_tokens + 128 <= local.context_length
      error_message = "Benchmark token overrides must fit the configured context with 128 tokens reserved for the chat template."
    }
    precondition {
      condition     = local.cpu_node_count >= local.cpu_requirements.node_count && local.cpu_ocpus >= local.cpu_requirements.ocpus && local.cpu_memory_gib >= local.cpu_requirements.memory_gib
      error_message = "CPU overrides must meet the component budget in discovery (including one benchmark job)."
    }
    precondition {
      condition     = can(regex("@sha256:[a-f0-9]{64}$", local.engine_image))
      error_message = "The selected image must have an assessed digest for the target CPU platform, or an explicit digest-pinned deployment override."
    }
    precondition {
      condition     = local.resolution == null || local.image_override == null || var.expert_configuration || try(local.image_override == local.assessed_engine.available_images[local.engine_platform], local.image_override == local.assessed_engine.image, false)
      error_message = "An unassessed image override requires expert_configuration; its model/platform compatibility is not established by discovery."
    }
    precondition {
      condition     = local.discovery_document == null || local.selected != null
      error_message = "Select one candidate/sizing-option ID from the supplied discovery JSON."
    }
    precondition {
      condition     = local.selected == null ? true : try(local.selected.configuration_status != "undetermined_requires_expert" || var.expert_configuration, false)
      error_message = "This assessment option has no determined deployment configuration. Supply explicit expert settings in deployment."
    }
    precondition {
      condition     = local.resolution == null || local.image_override != null || length(local.matching_engines) == 1
      error_message = "The requested engine version/channel was not assessed. Supply an explicit digest-pinned image and version override."
    }
    precondition {
      condition     = local.version_override == null || try(local.version_override == local.assessed_engine.version, false) || (var.expert_configuration && local.image_override != null)
      error_message = "Engine version must match frozen image evidence; an unassessed version needs an explicit expert image override."
    }
    precondition {
      condition     = !anytrue([for f in var.recipe_features : try(length(local.feature_options[f].modes) > 0, false) || try(local.feature_options[f].companion != null, false) || try(local.feature_options[f].hardware[local.gpu.recipe_hardware] == "unsupported", false)]) || (var.expert_configuration && var.engine_args != null)
      error_message = "Selected features need mode, companion or hardware-specific review. Supply explicit expert argv/env rather than silently dropping their settings."
    }
    precondition {
      condition     = alltrue([for f in var.recipe_features : contains(keys(local.feature_options), f)])
      error_message = "Select only features identified by discovery; otherwise supply explicit engine_args/env overrides without selecting an unknown feature."
    }
    precondition {
      condition     = try(local.profile.model.chat_template_available && (local.profile.model.pipeline_tag == "text-generation" || (local.suggested && try(local.resolution.recipe.serving_mode == "text", false))), false) && local.engine.image == local.engine_image && local.engine.version == local.engine_version && (var.expert_configuration || local.suggested || alltrue([for check in module.engine_check.assessment.engine_checks : check.architecture_supported && check.version_hints_satisfied]))
      error_message = "Selected image/version must match the frozen discovery configuration. Unsupported engine evidence requires explicit expert configuration."
    }
    precondition {
      condition = try(
        local.profile.model.resolved_revision == local.model_revision &&
        (var.expert_configuration && var.expert_rank_memory_gib != null ? var.expert_rank_memory_gib * pow(1024, 3) : coalesce(local.selected_rank_budget, local.rank_bytes)) > 0 &&
        (var.expert_configuration && var.expert_rank_memory_gib != null ? var.expert_rank_memory_gib * pow(1024, 3) : coalesce(local.selected_rank_budget, local.rank_bytes)) <= local.gpu.memory_bytes_per_gpu * 0.9 &&
      ((local.suggested && contains(local.engine.gpu_compute_capabilities, local.gpu.compute_capability)) || (local.profile.memory.status == "estimated" && contains(local.engine.gpu_compute_capabilities, local.gpu.compute_capability)) || (var.expert_configuration && var.expert_rank_memory_gib != null && local.gpu.compute_capability >= 75)), false)
      error_message = "Estimated/heuristic rank budget must fit. Unsupported estimation requires an explicit expert rank-memory bound; aggregate sizing is not a per-rank proof."
    }
    precondition {
      condition = try(contains([1, 2, 4, 8], local.tp) && local.tp <= local.gpu.gpus && local.pp >= 1 && floor(local.pp) == local.pp && local.replicas >= 1 && floor(local.replicas) == local.replicas && local.node_count == local.pp * local.replicas &&
        (var.expert_configuration || (local.pp <= local.a.layers && local.a.heads % local.tp == 0 && (local.a.kv_heads % local.tp == 0 || local.tp % local.a.kv_heads == 0))) &&
      (local.pp == 1 || local.engine.multi_node_backend == "mp") && (!local.requires_rdma || (local.gpu.compute_cluster_supported && contains(jsondecode(file("${path.module}/../../modules/accelerator-inventory/data/gpus.json")).compute_cluster_regions, local.region))), false)
      error_message = "TP must fit the GPU host, PP/replicas must match node count, and RDMA must be supported. Expert mode does not bypass allocation geometry."
    }
    precondition {
      condition = local.serving_configuration == null ? true : try(
        local.serving_configuration.model.resolved_revision == local.model_revision && local.serving_configuration.model.repository == local.model &&
        local.engine.platform == "linux/${local.gpu.cpu_architecture}" &&
      (var.expert_configuration || local.suggested || local.serving_configuration.status == "resolved_requires_validation"), false)
      error_message = "Frozen configuration must match the model revision and GPU node CPU platform. Unresolved recipe settings need explicit expert configuration."
    }
    precondition {
      condition = local.serving_configuration == null || var.expert_configuration || local.suggested ? true : try(
        local.serving_configuration.recipe.hardware[local.gpu.recipe_hardware] == "verified" &&
        local.serving_configuration.recipe.selected_hardware == local.gpu.recipe_hardware &&
        contains(local.serving_configuration.recipe.compatible_strategies, "single_node_tp") && local.pp == 1 &&
      local.tp == coalesce(try(tonumber(local.serving_configuration.recipe.variant_metadata.tp), null), try(tonumber(local.serving_configuration.recipe.strategy_overrides.single_node_tp.tp), null), try(tonumber(local.serving_configuration.recipe.strategy_overrides.single_node_tp.tp[local.gpu.recipe_hardware]), null)), false)
      error_message = "No matching tested recipe configuration for this GPU/TP/PP. Supply an explicit expert configuration; hardware similarity alone is not validation."
    }
    precondition {
      condition     = !local.suggested || try(local.profile.model.config_sources.config_repository == null, true) || (var.expert_configuration && var.engine_args != null)
      error_message = "This checkpoint uses a separate config repository. Stage its pinned config/tokenizer and provide expert argv; reusing the weights revision for that repository is invalid."
    }
    precondition {
      condition = !local.suggested || var.expert_configuration || try(
        local.tp == local.selected.tensor_parallel_size && local.pp == local.selected.pipeline_parallel_size &&
        local.context_length == local.discovery_input.profile.memory.assumptions.context_length &&
        local.concurrency == local.discovery_input.profile.memory.assumptions.concurrency &&
      local.kv_dtype == local.discovery_input.profile.memory.assumptions.kv_dtype, false)
      error_message = "Changing suggested topology or workload requires a fresh assessment or explicit expert settings."
    }
    precondition {
      condition     = alltrue([for a in local.engine_args : !contains(local.managed_flags, split("=", a)[0])]) && alltrue([for k, v in local.engine_env : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", k)) && !contains(["VLLM_HOST_IP", "LWS_GROUP_SIZE", "LWS_WORKER_INDEX", "LWS_LEADER_ADDRESS"], k)])
      error_message = "Serving argv/env cannot override managed identity, topology or reserved distributed settings; use dedicated deployment variables."
    }
    precondition {
      condition     = try(local.boot_volume_gib * pow(1024, 3) >= coalesce(try(local.profile.weights.checkpoint_download_bytes, null), local.profile.weights.tensor_data_bytes) * 1.3 + 50 * pow(1024, 3), false)
      error_message = "Boot volume must allow the complete checkpoint cache plus image/OS headroom on every worker."
    }
  }
}
module "allocation" {
  providers           = { oci = oci, oci.home = oci.home }
  count               = var.provision_resources ? 1 : 0
  source              = "../../modules/gpu-allocation"
  tenancy_ocid        = var.tenancy_ocid
  compartment_id      = local.compartment_id
  cluster_id          = var.cluster_id
  region              = local.region
  availability_domain = local.availability_domain
  subnet_id           = module.target.target.subnet_id
  gpu_image_id        = module.target.target.gpu_image.id
  cpu_image_id        = module.target.target.cpu_image.id
  cpu_subnet_id       = module.target.target.cpu_subnet_id
  cpu_node_count      = local.cpu_node_count
  cpu_shape           = local.cpu_requirements.shape
  cpu_ocpus           = local.cpu_ocpus
  cpu_memory_gib      = local.cpu_memory_gib
  gpu_nsg_ids         = try(module.target.target.gpu_nsg_ids, [])
  cpu_nsg_ids         = try(module.target.target.cpu_nsg_ids, [])
  pod_nsg_ids         = try(module.target.target.pod_nsg_ids, [])
  gpu_shape           = local.gpu_shape
  node_count          = local.node_count
  requires_rdma       = local.requires_rdma
  name                = var.name
  observation_id      = local.observation_id
  boot_volume_gib     = local.boot_volume_gib
  pod_subnet_id       = module.target.target.pod_subnet_id
  specification_id    = terraform_data.specification.id
}
module "delivery" {
  count          = var.provision_resources ? 1 : 0
  source         = "../../modules/devops-serving"
  tenancy_ocid   = var.tenancy_ocid
  compartment_id = local.compartment_id
  subnet_id      = module.target.target.devops_subnet_id
  nsg_ids        = try(module.target.target.devops_nsg_ids, [])
  name           = var.name
  config = {
    name                    = var.name, namespace = var.name, cluster_id = var.cluster_id, cluster_compartment_id = module.target.target.cluster_compartment_id, region = local.region
    model                   = local.model, model_revision = local.model_revision, engine_image = local.engine_image, engine_version = local.engine_version
    node_count              = local.node_count, gpu_shape = local.gpu_shape, tensor_parallel_size = local.tp, pipeline_parallel_size = local.pp, replicas = local.replicas
    context_length          = local.context_length, concurrency = local.concurrency, kv_dtype = local.kv_dtype, requires_rdma = local.requires_rdma
    kubernetes_version      = module.target.target.kubernetes_version, assessment_id = local.assessment_id
    serving_configuration   = local.serving_configuration, expert_configuration = var.expert_configuration
    engine_args             = local.engine_args, engine_env = local.engine_env, expert_rank_memory_gib = var.expert_rank_memory_gib
    rdma_network_attachment = var.rdma_network_attachment
    rdma_resource_name      = var.rdma_resource_name
    oke_addons              = module.target.target.oke_addons
    benchmark_requests      = var.benchmark_requests, benchmark_input_tokens = local.benchmark_input_tokens, benchmark_output_tokens = local.benchmark_output_tokens
  }
  depends_on = [module.allocation]
}
output "allocation" { value = try(module.allocation[0].allocation, null) }
output "delivery" { value = try(module.delivery[0].delivery, null) }
output "bootstrap_rbac" { value = try(module.delivery[0].delivery.bootstrap_rbac, null) }

output "deployment_preview" {
  value = {
    mode           = var.provision_resources ? "provision" : "preview_no_oci_resources",
    compartment_id = local.compartment_id, region = local.region, target = module.target.target,
    gpu_pool       = { name = var.name, shape = local.gpu_shape, node_count = local.node_count, image_id = module.target.target.gpu_image.id, subnet_id = module.target.target.subnet_id, availability_domain = local.availability_domain, boot_volume_gib = local.boot_volume_gib },
    cpu_pool       = { shape = local.cpu_requirements.shape, node_count = local.cpu_node_count, ocpus = local.cpu_ocpus, memory_gib = local.cpu_memory_gib, image_id = module.target.target.cpu_image.id, subnet_id = module.target.target.cpu_subnet_id, sizing = local.cpu_requirements },
    rdma           = { required = local.requires_rdma, allocation = local.requires_rdma ? "create_retained_compute_cluster_on_provision" : "not_required", network = local.requires_rdma ? "reuse_configured_oke_network_addon_verify_after_allocation" : "not_required" },
    cuda           = { status = "requires_runtime_validation", container = try(module.serving_runtime[0].runtime, { image = local.engine_image, status = "not_inspected_in_preview" }), worker_image = module.target.target.gpu_image.id, checks = ["Read actual NVIDIA driver version on every GPU host.", "Run the pinned serving image and verify CUDA initialization and kernels on each GPU model.", "A host CUDA toolkit version is not the container CUDA runtime or a driver compatibility proof; the minor compatibility floor may not cover PTX/JIT requirements."] }
  }
}

output "selected_configuration" {
  value = { selection_id = local.assessment_id, region = local.region, gpu_shape = local.gpu_shape, tp = local.tp, pp = local.pp, node_count = local.node_count, engine_image = local.engine_image, engine_args = local.engine_args, engine_env = local.engine_env, runtime_validation = "not_run", capacity_observed_at = try(local.selected.capacity_observed_at, null), configuration_status = try(local.selected.configuration_status, "manual"), warnings = concat(try(local.selected.warnings, []), local.suggested ? ["Suggested serving settings are untested; validate the pinned image, driver, kernels, memory and workload on the selected hardware."] : []), dependencies = try(local.serving_configuration.recipe.dependencies, []) }
}
