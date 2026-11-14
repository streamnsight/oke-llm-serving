# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "tenancy_ocid" {
  description = "RMS tenancy root; used for capacity reports."
  type        = string
}
variable "region" {
  description = "Internal initial OCI endpoint, normally injected by RMS. Null uses CLI defaults; the tenancy home region is discovered automatically."
  default     = null
  type        = string
}
variable "model" {
  description = "Public Hugging Face repository URL or owner/model."
  type        = string

  nullable = false
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
  description = "Simultaneously active sequences per serving replica at the specified context length; complete additional replicas repeat this memory budget."
  type        = number
  default     = 1
}
variable "observation_id" {
  description = "Snapshot label. Discovery requests fresh reports whenever its data source is read."
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
variable "compartment_ocid" {
  description = "Resource Manager stack compartment, automatically supplied by RMS."
  type        = string
  default     = null
}
variable "publish_infrastructure_bundles" {
  description = "Publish configured infrastructure ZIPs for confirmed options. The HTML report is always published on Apply, including when ZIP publication is disabled. Allocates no GPU hosts."
  type        = bool
  default     = true
}
variable "artifact_compartment_id" {
  description = "Optional artifact-storage compartment override. Defaults to the RMS stack compartment."
  type        = string
  default     = null
}
variable "par_lifetime_hours" {
  type    = number
  default = 24
}
variable "skip_gpu_allocation" {
  type        = bool
  default     = false
  description = "Temporary debug default for generated infrastructure stacks: skip GPU allocation while creating DevOps and CPU platform components."
}
variable "monitoring_enabled" {
  description = "Recommend Prometheus monitoring; existing compatible monitoring can be reused in the infrastructure stack."
  type        = bool
  default     = true
}
variable "autoscaling_enabled" {
  description = "Opt into request-aware workload scaling inside the retained GPU allocation. Does not enable node autoscaling."
  type        = bool
  default     = false
}
variable "model_storage_mode" {
  description = "Direct pinned Hub download, or recommend an optional retained Object Storage staging bucket and CPU download pipeline."
  type        = string
  default     = "direct_huggingface"
  validation {
    condition     = contains(["direct_huggingface", "object_storage"], var.model_storage_mode)
    error_message = "Choose direct_huggingface or object_storage."
  }
}
variable "include_diagnostics" {
  description = "Include expandable model, engine and regional diagnostic evidence in the HTML report. This does not run unselected engine/cache alternative lookups."
  type        = bool
  default     = false
}
