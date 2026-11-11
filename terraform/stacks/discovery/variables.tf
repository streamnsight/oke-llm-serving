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
}
variable "shape_names" {
  description = "Empty selects all visible GPU shapes."
  type        = set(string)
  default     = []
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
