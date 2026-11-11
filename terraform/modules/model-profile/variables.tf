variable "model" {
  description = "Hugging Face owner/model or repository URL."
  type        = string
  default     = null
}
variable "profile_json" {
  description = "Previously generated model-profile JSON; bypasses external execution for RMS."
  type        = string
  default     = null
  validation {
    condition     = var.profile_json == null ? true : try(jsondecode(var.profile_json).schema_version == "1.0" && length(jsondecode(var.profile_json).model.resolved_revision) == 40, false)
    error_message = "Supply a schema_version 1.0 model profile with a resolved 40-character revision."
  }
}
variable "enable_external_analysis" {
  description = "Explicitly allow bundled Python analysis. Leave false on RMS and supply profile_json instead."
  type        = bool
  default     = false
}
variable "revision" {
  description = "Model revision; use a commit SHA for repeatable subsequent reads."
  type        = string
  default     = "main"
}
variable "checkpoint" {
  description = "Optional repository-relative safetensors file/index selecting one variant."
  type        = string
  default     = null
}
variable "context_length" {
  description = "Total live tokens per sequence, including prompt and generated tokens."
  type        = number
  default     = 4096
  validation {
    condition     = var.context_length > 0 && floor(var.context_length) == var.context_length
    error_message = "context_length must be a positive integer."
  }
}
variable "concurrency" {
  description = "Simultaneously active sequences, each using the requested context length."
  type        = number
  default     = 1
  validation {
    condition     = var.concurrency > 0 && floor(var.concurrency) == var.concurrency
    error_message = "concurrency must be a positive integer."
  }
}
variable "kv_dtype" {
  description = "Assumed KV dtype; runtime support is assessed separately."
  type        = string
  default     = "bfloat16"
  validation {
    condition     = contains(["bfloat16", "float16", "float32"], var.kv_dtype)
    error_message = "Use bfloat16, float16 or float32."
  }
}
variable "weight_dtype" {
  description = "checkpoint preserves tensor data bytes; a float dtype models an explicit conversion."
  type        = string
  default     = "checkpoint"
  validation {
    condition     = contains(["checkpoint", "bfloat16", "float16", "float32"], var.weight_dtype)
    error_message = "Use checkpoint, bfloat16, float16 or float32."
  }
}
variable "runtime_gib" {
  description = "Unmeasured aggregate runtime allowance in GiB; not a per-rank engine overhead estimate."
  type        = number
  default     = 2
  validation {
    condition     = var.runtime_gib >= 0
    error_message = "runtime_gib must be nonnegative."
  }
}
variable "margin" {
  description = "Fraction added to weights, KV and runtime allowance."
  type        = number
  default     = 0.2
  validation {
    condition     = var.margin >= 0 && var.margin <= 1
    error_message = "margin must be between zero and one."
  }
}
variable "python_executable" {
  description = "Python 3.11+ executable available on the Terraform runner."
  type        = string
  default     = "python3"
}
