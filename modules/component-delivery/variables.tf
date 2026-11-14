# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variable "project_id" { type = string }
variable "compartment_id" { type = string }
variable "cluster_deploy_environment_id" { type = string }
variable "cluster_id" { type = string }
variable "region" { type = string }
variable "subnet_id" { type = string }
variable "nsg_ids" {
  type    = list(string)
  default = []
}
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,39}$", var.name))
    error_message = "name must be a lowercase DNS label of at most 40 characters."
  }
}
variable "source_repository_id" {
  type        = string
  description = "Existing immutable Generic Artifact Registry repository for scripts, specifications and values."
}
variable "result_repository_id" {
  type        = string
  description = "Existing Generic Artifact Registry repository for immutable per-deployment evidence."
}
variable "helm_version" {
  type    = string
  default = "v3.19.0"
  validation {
    condition     = can(regex("^v3\\.[0-9]+\\.[0-9]+$", var.helm_version))
    error_message = "The Shell helper requires an explicit Helm 3 release."
  }
}
variable "registry_host" {
  type        = string
  default     = null
  description = "OCIR host override for other realms; defaults to the commercial region.ocir.io endpoint."
}
variable "components" {
  description = "Declaration-based lifecycle: managed deploys/upgrades, reuse validates an external release, retire retains only the explicit uninstall pipeline. Values may contain literal $${PARAMETER} placeholders; parameters supply their editable defaults. dependencies are prerequisite Helm releases; blocker_kinds are Kubernetes resource types whose instances prevent uninstall. No arbitrary commands are accepted."
  type = map(object({
    mode            = string
    namespace       = string
    release_name    = string
    ownership_token = string
    chart = object({
      repository = string
      name       = string
      version    = string
    })
    values_yaml      = optional(string, "{}")
    parameters       = optional(map(string), {})
    dependencies     = optional(list(object({ namespace = string, release_name = string })), [])
    blocker_kinds    = optional(list(string), [])
    crd_names        = optional(list(string), [])
    deployment_names = optional(list(string), [])
    timeout_seconds  = optional(number, 600)
  }))
  validation {
    condition = alltrue([for key, c in var.components :
      can(regex("^[a-z][a-z0-9-]{0,39}$", key)) && contains(["managed", "reuse", "retire"], c.mode) &&
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", c.namespace)) && length(c.namespace) <= 63 &&
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", c.release_name)) && length(c.release_name) <= 53 &&
      length(c.ownership_token) >= 16 && c.timeout_seconds >= 60 && c.timeout_seconds <= 1800 &&
      c.timeout_seconds == floor(c.timeout_seconds) &&
      can(regex("^(https://|oci://)", c.chart.repository)) &&
      can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*$", c.chart.name)) &&
      can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+([+-][A-Za-z0-9.-]+)?$", c.chart.version)) &&
      alltrue([for k in keys(c.parameters) : can(regex("^[A-Z][A-Z0-9_]*$", k)) && !contains([
        "REGION", "CLUSTER_ID", "NAMESPACE", "RELEASE_NAME", "CHART_VERSION", "CONFIRM_UNINSTALL", "RECOVER_LOCK_HOLDER",
        "OCI_DEPLOYMENT_ID", "OCI_PIPELINE_ID", "ENFORCE_HELM_DEPLOYMENT", "OCI_DEVOPS_DEPLOY_USE_CREATE_NAMESPACE_FLAG",
        "PATH", "HOME", "ENV", "BASH_ENV", "SHELLOPTS", "BASHOPTS", "IFS", "LD_PRELOAD", "LD_LIBRARY_PATH", "KUBECONFIG"
      ], k) && !startswith(k, "OCI_") && !startswith(k, "DELIVERY_") && !startswith(k, "HELM_")]) &&
      alltrue([for k in concat(c.blocker_kinds, c.crd_names, c.deployment_names) : can(regex("^[a-z0-9][a-z0-9.-]*$", k))]) &&
      can(yamldecode(c.values_yaml))
    ])
    error_message = "Components require valid lifecycle modes, DNS names, explicit chart versions, stable ownership tokens, bounded timeouts and non-reserved uppercase parameter names."
  }
  validation {
    condition     = length(distinct([for c in var.components : "${c.namespace}/${c.release_name}"])) == length(var.components)
    error_message = "A release/namespace may occur only once in this module."
  }
}
