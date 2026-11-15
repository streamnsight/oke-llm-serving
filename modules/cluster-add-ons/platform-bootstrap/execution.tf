# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  # Read-only inventory/image observations must not rerun unchanged components.
  bootstrap_revision = sha256(jsonencode({
    components = module.components.generations,
    code = merge(
      { for name in fileset(path.module, "*.tf") : "platform/${name}" => filesha256("${path.module}/${name}") },
      { for name in local.scripts : "scripts/${name}" => filesha256("${path.module}/scripts/${name}") },
      { for name in fileset("${path.module}/../../shared/component-delivery", "*.tf") : "delivery/${name}" => filesha256("${path.module}/../../shared/component-delivery/${name}") },
      { for name in fileset("${path.module}/../../shared/inline-command-spec", "*.tf") : "inline/${name}" => filesha256("${path.module}/../../shared/inline-command-spec/${name}") }
    ),
    binding = {
      region             = var.config.region, cluster_id = var.config.cluster_id, platform = var.name,
      kubernetes_version = var.config.target.kubernetes_version,
      subnet_id          = var.subnet_id, nsg_ids = sort(var.nsg_ids), allocation = var.config.allocation,
      authorization      = try(var.config.cluster_authorization_mode, "iam"),
      gpu_checks         = { for key in ["gpu_allocation_enabled", "gpu_shape", "node_count", "gpu_count_per_host", "requires_rdma", "rdma_resource_name"] : key => try(var.config[key], null) }
    }
  }))
}
resource "terraform_data" "bootstrap_revision" {
  input = local.bootstrap_revision
}
resource "oci_devops_deployment" "bootstrap" {
  deploy_pipeline_id            = oci_devops_deploy_pipeline.platform["deploy"].id
  deployment_type               = "PIPELINE_DEPLOYMENT"
  trigger_new_devops_deployment = false
  display_name                  = "${var.name}-${substr(local.bootstrap_revision, 0, 12)}"
  # The provider waits for SUCCEEDED. FAILED/CANCELED or a timeout fail Apply.
  timeouts { create = "90m" }
  lifecycle {
    replace_triggered_by = [terraform_data.bootstrap_revision]
    postcondition {
      condition     = self.state == "SUCCEEDED"
      error_message = "The component coordinator did not succeed. Inspect this DevOps deployment and its child runs before retrying Apply."
    }
  }
  # Metadata creation order is insufficient: all child stages, inputs and IAM
  # definitions must exist before the coordinator can start its component graph.
  depends_on = [module.components, oci_devops_deploy_pipeline.platform, oci_devops_deploy_artifact.platform, oci_devops_deploy_stage.platform, oci_identity_policy.bootstrap, oci_logging_log.platform]
}
