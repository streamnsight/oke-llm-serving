# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  onboarding_pipeline_id = try(coalesce(var.platform.model_onboarding_pipeline_id, ""), "")
  execution_pool_id      = try(coalesce(var.platform.allocation.gpu_pool_id, ""), "")
  onboarding_arguments = {
    MODEL_NAMESPACE        = local.namespace, MODEL_PROJECT_ID = var.platform.project_id,
    MODEL_GPU_POOL_ID      = local.execution_pool_id, MODEL_PIPELINE_IDS = jsonencode(sort(local.all_pipeline_ids)),
    MODEL_ACCESS_OPERATION = "grant"
  }
  execution_arguments = merge(local.defaults, { CHART_VERSION = local.chart_version })
  # No timestamps, capacity snapshots, add-on inventories or observed retained
  # node counts. Effective runtime configuration also drives DELIVERY_GENERATION.
  model_execution_revision = sha256(jsonencode({
    workload_generation = module.delivery.generations.workload,
    validation_command  = sha256(module.inline_operation["validate"].content),
    onboarding          = { pipeline_id = local.onboarding_pipeline_id, revision = try(var.platform.model_onboarding_revision, null), arguments = local.onboarding_arguments },
    binding = {
      environment_id       = var.platform.deploy_environment_id,
      source_repository_id = var.platform.script_repository_id,
      subnet_id            = var.platform.runner_subnet_id, nsg_ids = sort(var.platform.runner_nsg_ids)
    },
    # Terraform delivery changes (including native stage/source encoding) must
    # execute the corrected pipeline even if model flags remain identical.
    delivery_code = merge(
      { for asset in ["main.tf", "operations.tf", "execution.tf"] : "model/${asset}" => filesha256("${path.module}/${asset}") },
      { for asset in fileset("${path.module}/../../shared/component-delivery", "*.tf") : "delivery/${asset}" => filesha256("${path.module}/../../shared/component-delivery/${asset}") },
      { for asset in fileset("${path.module}/../../shared/inline-command-spec", "*.tf") : "inline/${asset}" => filesha256("${path.module}/../../shared/inline-command-spec/${asset}") }
    )
  }))
}
resource "terraform_data" "model_execution_revision" { input = local.model_execution_revision }

resource "oci_devops_deployment" "onboarding" {
  deploy_pipeline_id            = local.onboarding_pipeline_id
  deployment_type               = "PIPELINE_DEPLOYMENT"
  trigger_new_devops_deployment = false
  display_name                  = "${local.name}-onboard-${substr(local.model_execution_revision, 0, 12)}"
  deployment_arguments {
    dynamic "items" {
      for_each = local.onboarding_arguments
      content {
        name  = items.key
        value = items.value
      }
    }
  }
  timeouts { create = "45m" }
  lifecycle {
    replace_triggered_by = [terraform_data.model_execution_revision]
    precondition {
      condition     = local.onboarding_pipeline_id != "" && local.execution_pool_id != "" && local.execution_pool_id != "runtime"
      error_message = "Apply the retained GPU infrastructure and required shared components first. Automatic model deployment requires its actual GPU pool and trusted model-onboarding pipeline; this model stack never allocates GPUs or grants itself cluster administration."
    }
    postcondition {
      condition     = self.state == "SUCCEEDED"
      error_message = "Trusted model namespace onboarding did not succeed. Inspect its DevOps deployment before retrying Apply; the workload has not been started by this execution."
    }
  }
  # Trusted onboarding inspects every model pipeline and its fixed defaults.
  # Wait for complete definitions/inputs and scoped IAM, not only project IDs.
  depends_on = [module.delivery, oci_devops_deploy_pipeline.operation, oci_devops_deploy_artifact.operation, oci_devops_deploy_stage.operation, oci_identity_dynamic_group.model, oci_identity_policy.model]
}
resource "oci_devops_deployment" "workload" {
  deploy_pipeline_id            = module.delivery.component_pipeline_ids.workload
  deployment_type               = "PIPELINE_DEPLOYMENT"
  trigger_new_devops_deployment = false
  display_name                  = "${local.name}-deploy-${substr(local.model_execution_revision, 0, 12)}"
  deployment_arguments {
    dynamic "items" {
      for_each = merge(local.execution_arguments, { ENFORCE_HELM_DEPLOYMENT = "true" })
      content {
        name  = items.key
        value = items.value
      }
    }
  }
  # prepare, native Helm and finish are each bounded by timeout_seconds.
  timeouts { create = "${ceil((3 * var.timeout_seconds + 900) / 60)}m" }
  lifecycle {
    replace_triggered_by = [terraform_data.model_execution_revision, oci_devops_deployment.onboarding]
    postcondition {
      condition     = self.state == "SUCCEEDED"
      error_message = "Model Helm deployment or its finish checks failed. Inspect the workload DevOps deployment/lease before retrying Apply; no benchmark was started."
    }
  }
  depends_on = [oci_devops_deployment.onboarding, module.delivery, oci_identity_policy.model]
}
resource "oci_devops_deployment" "validation" {
  deploy_pipeline_id            = oci_devops_deploy_pipeline.operation["validate"].id
  deployment_type               = "PIPELINE_DEPLOYMENT"
  trigger_new_devops_deployment = false
  display_name                  = "${local.name}-validate-${substr(local.model_execution_revision, 0, 12)}"
  deployment_arguments {
    dynamic "items" {
      for_each = local.execution_arguments
      content {
        name  = items.key
        value = items.value
      }
    }
  }
  timeouts { create = "75m" }
  lifecycle {
    replace_triggered_by = [terraform_data.model_execution_revision, oci_devops_deployment.workload]
    postcondition {
      condition     = self.state == "SUCCEEDED"
      error_message = "The model's independent validation pipeline failed. Apply cannot report a successful model setup; inspect that DevOps deployment before retrying."
    }
  }
  depends_on = [oci_devops_deployment.workload, oci_devops_deploy_artifact.operation, oci_devops_deploy_stage.operation, oci_identity_policy.model]
}
