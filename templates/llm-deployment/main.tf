# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12" } }
}
locals {
  platform   = try(jsondecode(file("${path.module}/inputs/platform-binding.json")), null)
  model      = try(jsondecode(file("${path.module}/inputs/model-spec.json")), null)
  configured = local.platform != null && local.model != null
}
provider "oci" { region = try(coalesce(var.region, local.platform.region), null) }
data "oci_identity_tenancy" "target" { tenancy_id = var.tenancy_ocid }
data "oci_identity_regions" "available" {}
provider "oci" {
  alias  = "home"
  region = one([for r in data.oci_identity_regions.available.regions : r.name if r.key == data.oci_identity_tenancy.target.home_region_key])
}
resource "terraform_data" "binding" {
  input = { configured = local.configured }
  lifecycle {
    precondition {
      condition     = local.configured
      error_message = "Use a configured model ZIP published by the infrastructure stack: inputs/platform-binding.json and inputs/model-spec.json are required."
    }
    precondition {
      condition     = !local.configured || var.region == null ? true : var.region == local.platform.region
      error_message = "This model ZIP reuses infrastructure in another region. Open its generated regional RMS URL."
    }
  }
}
module "model" {
  count          = local.configured ? 1 : 0
  source         = "../../modules/llm-deployment/model-delivery"
  providers      = { oci = oci, oci.home = oci.home }
  tenancy_ocid   = var.tenancy_ocid
  compartment_id = try(local.platform.compartment_id, "")
  platform       = local.platform
  model          = local.model
  name           = var.model_name
  namespace      = var.namespace
  overrides = {
    model_id             = var.model_id, model_revision = var.model_revision, serving_image = var.serving_image,
    tensor_parallel_size = var.tensor_parallel_size, pipeline_parallel_size = var.pipeline_parallel_size,
    hosts_per_replica    = var.hosts_per_replica, gpus_per_pod = var.gpus_per_pod, replicas = var.replicas,
    context_length       = var.context_length, concurrency = var.concurrency
  }
  storage           = { mode = var.storage_mode, pvc_name = var.model_pvc_name, model_path = var.model_path, workspace_gib = var.workspace_gib }
  hf_token_secret   = var.hf_token_secret
  router_enabled    = var.router_enabled
  inference_probe   = var.inference_probe
  benchmark_backend = var.benchmark_backend
  autoscaling       = { enabled = var.autoscaling_enabled, min_replicas = var.min_replicas, max_replicas = var.max_replicas, prometheus_url = var.prometheus_url, target_inflight = var.target_inflight }
  depends_on        = [terraform_data.binding]
}
output "model_delivery" { value = try(module.model[0].model_delivery, null) }
output "onboarding_arguments" { value = try(module.model[0].onboarding_arguments, null) }
