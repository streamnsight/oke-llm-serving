# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

locals {
  repository = trimsuffix(trimprefix(var.model, "https://huggingface.co/"), "/")
}

# Public Hub metadata only. No external program, model code or weight download.
data "http" "model" {
  url                = "https://huggingface.co/api/models/${local.repository}/revision/${urlencode(var.revision)}?blobs=true"
  request_headers    = { Accept = "application/json" }
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && can(regex("^[a-fA-F0-9]{40}$", jsondecode(self.response_body).sha))
      error_message = "Hub model lookup failed or did not resolve a commit SHA. Initial native discovery supports public models."
    }
  }
}

locals {
  info                   = jsondecode(data.http.model.response_body)
  sha                    = local.info.sha
  metadata_chat_template = try(local.info.config.tokenizer_config.chat_template, null)
  tokenizer_lookup       = try(length(local.metadata_chat_template) > 0, false) ? false : contains([for file in try(local.info.siblings, []) : file.rfilename], "tokenizer_config.json")
}

data "http" "tokenizer" {
  count              = local.tokenizer_lookup ? 1 : 0
  url                = "https://huggingface.co/${local.repository}/raw/${local.sha}/tokenizer_config.json"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = contains([200, 404], self.status_code)
      error_message = "Tokenizer lookup failed; access/network errors are not evidence of missing chat support."
    }
  }
}

data "http" "config" {
  url                = "https://huggingface.co/${local.repository}/resolve/${local.sha}/config.json"
  request_headers    = { Accept = "application/json" }
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = (self.status_code == 200 && can(keys(jsondecode(self.response_body)))) || self.status_code == 404
      error_message = "Could not read config.json at the resolved revision."
    }
  }
}

# Evidence only: prose matches are not a complete dependency specification.
data "http" "card" {
  url                = "https://huggingface.co/${local.repository}/raw/${local.sha}/README.md"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = contains([200, 404], self.status_code)
      error_message = "Model-card lookup failed; permission/network errors must not be treated as absent requirements."
    }
  }
}

locals {
  version_pattern = "(?i)\\b(vllm|sglang)[ \\t`]*(?:version[ \\t]*)?(>=|<=|==|~=|>|<|=)[ \\t`]*v?([0-9]+\\.[0-9]+(?:\\.[0-9]+)?(?:[a-z][a-z0-9]*|[.+-][a-z0-9]+)*)"
  card_lines      = data.http.card.status_code == 200 ? split("\n", data.http.card.response_body) : []
  version_hints = flatten([for index, line in local.card_lines : [
    for match in regexall(local.version_pattern, line) : {
      engine     = lower(match[0]), operator = match[1], version = match[2]
      source_url = data.http.card.url, line = index + 1, text = substr(line, 0, 500)
    }
  ]])
}

locals {
  config                    = jsondecode(data.http.config.status_code == 200 ? data.http.config.response_body : try(data.http.fallback_config[0].response_body, "{}"))
  text                      = try(local.config.text_config, local.config)
  model_type                = try(local.text.model_type, local.config.model_type, "unknown")
  experts                   = try(local.text.num_local_experts, local.text.num_experts, null)
  moe                       = contains(["mixtral", "qwen2_moe", "qwen3_moe"], local.model_type) || try(local.experts > 1, false)
  conventional              = contains(["llama", "mistral", "mixtral", "qwen2", "qwen2_moe", "qwen3", "qwen3_moe"], local.model_type)
  dtype_bytes               = { F64 = 8, F32 = 4, F16 = 2, BF16 = 2 }
  parameters                = try(local.info.safetensors.parameters, {})
  counts_valid              = try(length(local.parameters) > 0 && alltrue([for dtype, count in local.parameters : contains(keys(local.dtype_bytes), dtype) && count >= 0 && floor(count) == count]) && sum(values(local.parameters)) == local.info.safetensors.total, false)
  weight_bytes              = local.counts_valid ? sum([for dtype, count in local.parameters : count * lookup(local.dtype_bytes, dtype, 0)]) : null
  resident_weight_bytes     = local.counts_valid ? max(local.weight_bytes, sum(values(local.parameters)) * (var.kv_dtype == "float32" ? 4 : 2)) : null
  layers                    = try(local.text.num_hidden_layers, 0)
  heads                     = try(local.text.num_attention_heads, 0)
  kv_heads                  = try(local.text.num_key_value_heads, local.heads)
  head_dim                  = try(local.text.head_dim, local.text.hidden_size / local.heads, 0)
  dimensions_valid          = try(alltrue([for n in [local.layers, local.heads, local.kv_heads, local.head_dim] : n > 0 && floor(n) == n]) && local.kv_heads <= local.heads && local.heads % local.kv_heads == 0, false)
  max_context               = try(local.text.max_position_embeddings, null)
  quantization              = try(local.config.quantization_config, local.text.quantization_config, null)
  root_checkpoints          = [for file in try(local.info.siblings, []) : file.rfilename if endswith(file.rfilename, ".safetensors") && !strcontains(file.rfilename, "/")]
  checkpoint_file_sizes     = [for file in try(local.info.siblings, []) : try(file.size, file.lfs.size, null) if contains(local.root_checkpoints, file.rfilename)]
  checkpoint_download_bytes = try(length(local.checkpoint_file_sizes) > 0 && alltrue([for size in local.checkpoint_file_sizes : size > 0]) ? sum(local.checkpoint_file_sizes) : null, null)
  has_index                 = contains([for file in try(local.info.siblings, []) : file.rfilename], "model.safetensors.index.json")
  canonical                 = local.has_index || (length(local.root_checkpoints) == 1 && contains(local.root_checkpoints, "model.safetensors"))
  reasons = compact([
    length(keys(local.config)) > 0 ? "" : "No config.json or explicit recipe fallback is available.",
    local.conventional ? "" : "Architecture requires a dedicated estimator.",
    local.counts_valid ? "" : "Hub safetensors counts are missing, inconsistent or use unsupported dtypes.",
    local.canonical ? "" : "No unambiguous canonical safetensors checkpoint is declared.",
    local.dimensions_valid ? "" : "Missing or unsupported attention dimensions.",
    local.quantization == null ? "" : "Quantized checkpoints need engine-specific resident-memory estimates.",
    anytrue([for key in ["text_config", "vision_config", "auto_map"] : contains(keys(local.config), key)]) ? "Composite, multimodal or custom-code architecture requires a dedicated estimator." : "",
    try(var.context_length > local.max_context, false) ? "Requested context exceeds the declared maximum." : "",
  ])
  supported          = length(local.reasons) == 0
  kv_bytes_per_token = local.supported ? 2 * local.layers * local.kv_heads * local.head_dim * (var.kv_dtype == "float32" ? 4 : 2) : null
  kv_bytes           = local.supported ? local.kv_bytes_per_token * var.context_length * var.concurrency : null
  runtime_bytes      = ceil(var.runtime_gib * pow(1024, 3))
  subtotal           = local.supported ? local.resident_weight_bytes + local.kv_bytes + local.runtime_bytes : null
  total              = local.supported ? ceil(local.subtotal * (1 + var.margin)) : null
}

output "profile" {
  description = "Metadata-based profile; check memory.status before interpreting numeric estimates."
  value = {
    schema_version    = "1.0"
    estimator_version = "terraform-metadata-0.1.0"
    model = {
      repository              = local.repository
      requested_revision      = var.revision
      resolved_revision       = local.sha
      url                     = "https://huggingface.co/${local.repository}/tree/${local.sha}"
      gated                   = try(local.info.gated, false)
      pipeline_tag            = try(local.info.pipeline_tag, try(contains(local.fallback_metadata.meta.tasks, "text"), false) ? "text-generation" : null)
      license                 = try(local.info.cardData.license, null)
      config_sources          = { config_repository = local.config_repository, tokenizer_repository = local.tokenizer_repository, revisions = { for k, r in data.http.fallback_model : k => jsondecode(r.response_body).sha } }
      chat_template_available = try(length(jsondecode(data.http.fallback_tokenizer[0].response_body).chat_template) > 0, false) || try(length(local.metadata_chat_template) > 0, false) || try(length(jsondecode(data.http.tokenizer[0].response_body).chat_template) > 0, false) || contains([for file in try(local.info.siblings, []) : file.rfilename], "chat_template.jinja")
    }
    architecture = {
      model_type              = local.model_type
      kind                    = local.moe ? "moe" : local.conventional ? "dense" : "unknown"
      experts                 = local.experts
      experts_per_token       = try(local.text.num_experts_per_tok, null)
      architectures           = try(local.config.architectures, [])
      declared_context_length = local.max_context
      quantization            = local.quantization
      source                  = "SHA-pinned config.json"
      confidence              = "declared_metadata"
      attention = {
        layers      = local.layers, heads = local.heads, kv_heads = local.kv_heads, head_dim = local.head_dim
        hidden_size = try(local.text.hidden_size, null), vocab_size = try(local.text.vocab_size, null)
        layer_types = try(local.text.layer_types, null)
      }
    }
    serving_requirements = {
      status         = length(local.version_hints) > 0 ? "version_hints_found" : "unspecified"
      card_status    = data.http.card.status_code == 200 ? "read" : "absent"
      version_hints  = local.version_hints
      interpretation = "Regex evidence only; examples may not state mandatory minimum versions. No match does not imply incompatibility."
    }
    weights = {
      selected_checkpoint       = local.has_index ? "model.safetensors.index.json" : local.canonical ? "model.safetensors" : null
      checkpoint_download_bytes = try(coalesce(local.checkpoint_download_bytes, one([for f in local.info.siblings : try(f.size, f.lfs.size) if endswith(f.rfilename, ".gguf")])), null)
      storage_source            = "Hub-published root safetensors file sizes; storage only, never resident GPU memory"
      tensor_data_bytes         = local.weight_bytes
      tensor_elements           = try(local.info.safetensors.total, null)
      elements_by_dtype         = local.parameters
      source                    = "Hub-published safetensors counts by dtype; not independently verified headers"
      confidence                = "declared_metadata"
    }
    memory = {
      status                      = local.supported ? "estimated" : "unsupported"
      reasons                     = local.reasons
      weight_bytes                = local.supported ? local.resident_weight_bytes : null
      kv_bytes_per_token          = local.kv_bytes_per_token
      kv_bytes                    = local.kv_bytes
      runtime_allowance_bytes     = local.runtime_bytes
      minimum_aggregate_bytes     = local.subtotal
      recommended_aggregate_bytes = local.total
      recommended_aggregate_gib   = local.supported ? local.total / pow(1024, 3) : null
      assumptions = {
        context_length         = var.context_length
        concurrency            = var.concurrency
        live_cached_tokens     = var.context_length * var.concurrency
        kv_dtype               = var.kv_dtype
        weight_dtype           = var.kv_dtype
        runtime_allowance_gib  = var.runtime_gib
        safety_margin_fraction = var.margin
        prefix_sharing         = false
        offload                = false
        parallelism            = "unsharded aggregate; not a per-GPU fit assessment"
      }
    }
    warnings = [
      "The serving recipe uses the requested floating compute/KV dtype. Resident weights reserve the greater of checkpoint bytes and dtype-converted element bytes.",
      "Hub-published parameter counts are trusted metadata, not independently read tensor headers.",
      "All expert weights and full-context KV for all layers are counted; sliding-window savings are not assumed.",
      "Runtime allowance and margin are assumptions, not measured overhead or a performance guarantee.",
      "GPU count/layout requires per-rank VRAM, topology and serving-engine assessment.",
    ]
  }
}
