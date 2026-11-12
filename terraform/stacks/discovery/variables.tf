# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "tenancy_ocid" {
  description = "RMS tenancy root; used for capacity reports."
  type        = string
}
variable "region" {
  description = "RMS/bootstrap region for subscription lookup; not the deployment selection."
  type        = string
}
variable "model" {
  description = "Public Hugging Face repository URL or owner/model."
  type        = string
  default     = null
}
variable "model_choice" {
  description = "Legacy catalog selection for existing stacks. An explicit model URL/ID takes priority."
  type        = string
  default     = "custom"
}
variable "revision" {
  type    = string
  default = "main"
}
variable "context_length" {
  description = "Live tokens per sequence, including input and output."
  type        = number
  default     = 4096
}
variable "concurrency" {
  description = "Simultaneously active sequences at the specified context length."
  type        = number
  default     = 1
}
variable "kv_dtype" {
  type    = string
  default = "bfloat16"
}
variable "runtime_gib" {
  type    = number
  default = 2
}
variable "margin" {
  type    = number
  default = 0.2
}
variable "observation_id" {
  description = "Change for each new capacity observation; refresh alone preserves the old reports."
  type        = string
  default     = "initial"
}
variable "regions" {
  description = "Empty selects every READY subscription. Optional subset for reruns/troubleshooting."
  type        = set(string)
  default     = []
  nullable    = false
}
variable "shape_names" {
  description = "Empty selects all visible GPU shapes."
  type        = set(string)
  default     = []
  nullable    = false
}
variable "compartment_id" {
  description = "Intended deployment compartment for quota headroom; null checks root entitlement only."
  type        = string
  default     = null
}
variable "query_resource_availability" {
  description = "Query supported compute limit headroom. Disable only for capacity-only investigation."
  type        = bool
  default     = true
}

variable "only_shapes_with_limits" {
  description = "Skip capacity checks for shapes with a confirmed zero limit. False also finds capacity that needs a limit increase. Unknown mappings remain included."
  type        = bool
  default     = false
}
