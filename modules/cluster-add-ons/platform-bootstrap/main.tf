# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12", configuration_aliases = [oci.home] } }
}
data "oci_core_subnet" "runner" { subnet_id = var.subnet_id }
resource "oci_ons_notification_topic" "platform" {
  compartment_id = var.compartment_id
  name           = "${var.name}-platform"
}
resource "oci_devops_project" "platform" {
  compartment_id = var.compartment_id
  name           = var.name
  description    = "Cluster-owned LLM platform components; serving workloads have a separate lifecycle."
  notification_config { topic_id = oci_ons_notification_topic.platform.id }
  lifecycle {
    precondition {
      condition     = try(var.config.target.ready, true)
      error_message = "The existing OKE target must pass discovery checks."
    }
  }
}
resource "oci_logging_log_group" "platform" {
  compartment_id = var.compartment_id
  display_name   = "${var.name}-platform"
}
resource "oci_logging_log" "platform" {
  display_name = "${var.name}-platform"
  log_group_id = oci_logging_log_group.platform.id
  log_type     = "SERVICE"
  is_enabled   = true
  configuration {
    compartment_id = var.compartment_id
    source {
      category    = "all"
      resource    = oci_devops_project.platform.id
      service     = "devops"
      source_type = "OCISERVICE"
    }
  }
}
resource "oci_artifacts_repository" "scripts" {
  compartment_id  = var.compartment_id
  display_name    = "${var.name}-scripts"
  description     = "Immutable pipeline software, values and specifications; no model weights."
  repository_type = "GENERIC"
  is_immutable    = true
  provisioner "local-exec" {
    when    = destroy
    command = "bash '${path.module}/scripts/cleanup-repository.sh'"
    environment = {
      REPOSITORY_ID  = self.id
      COMPARTMENT_ID = self.compartment_id
    }
  }
}
resource "oci_devops_deploy_environment" "cluster" {
  project_id              = oci_devops_project.platform.id
  display_name            = "${var.name}-oke"
  deploy_environment_type = "OKE_CLUSTER"
  cluster_id              = var.config.cluster_id
  network_channel {
    network_channel_type = "PRIVATE_ENDPOINT_CHANNEL"
    subnet_id            = var.subnet_id
    nsg_ids              = var.nsg_ids
  }
  lifecycle {
    precondition {
      condition     = try(length(data.oci_core_subnet.runner.ipv6cidr_blocks) == 0, true) && try(coalesce(data.oci_core_subnet.runner.ipv6cidr_block, "") == "", true)
      error_message = "OCI DevOps private OKE environments require a subnet without IPv6 enabled."
    }
  }
}
locals {
  scripts    = toset(["platform.sh", "readiness.jq"])
  generation = sha256(jsonencode({ specification = var.config, components = local.component_specs, scripts = { for script in local.scripts : script => filesha256("${path.module}/scripts/${script}") } }))
  config = merge(var.config, {
    platform_name = var.name, generation = local.generation, helm_version = local.chart_defaults.helm_version,
    enable_lws    = local.required.lws, cpu_components_required = length(local.component_specs) > 0, cpu_budget = local.component_budget,
    components = { for key, c in local.component_specs : key => merge(c, {
      generation      = module.components.generations[key],
      owner_name      = module.components.owner_names[key],
      pipeline_id     = try(module.components.component_pipeline_ids[key], null),
      dependency_keys = [for dep in c.dependencies : one([for k, other in local.component_specs : k if other.release_name == dep.release_name && other.namespace == dep.namespace])]
    }) }
  })
  parameters = { REGION = var.config.region, CLUSTER_ID = var.config.cluster_id, PLATFORM_NAME = var.name }
  command_specs = { for mode in ["deploy", "validate"] : mode => yamlencode({
    version = "0.1", component = "command", timeoutInSeconds = 3600, shell = "bash", failImmediatelyOnError = true,
    env = { variables = merge({ for key in keys(local.parameters) : key => "$${${key}}" }, {
      PLATFORM_MODE = mode,
      OCI_CLI_AUTH  = "resource_principal", OCI_CLI_REGION = "$${REGION}"
    }) },
    inputArtifacts = [],
    steps = [{ type = "Command", name = mode == "deploy" ? "deploy-component-graph" : "validate-platform", timeoutInSeconds = 3600, command = join("\n", concat([
      "set -euo pipefail", "export REGION CLUSTER_ID PLATFORM_NAME PLATFORM_MODE OCI_CLI_AUTH OCI_CLI_REGION OCI_DEPLOYMENT_ID OCI_PIPELINE_ID"
    ], [for script in sort(tolist(local.scripts)) : "printf '%s  %s\\n' '${filesha256("${path.module}/scripts/${script}")}' '${script}' | sha256sum -c -"], ["printf '%s  platform.json\\n' '${sha256(jsonencode(local.config))}' | sha256sum -c -", "bash ./platform.sh"])) }]
  }) }
  all_pipeline_ids = concat(module.components.all_pipeline_ids, [for pipeline in oci_devops_deploy_pipeline.platform : pipeline.id], [oci_devops_deploy_pipeline.model_onboarding.id])
}
module "inline_platform" {
  for_each      = local.command_specs
  source        = "../../shared/inline-command-spec"
  specification = yamldecode(each.value)
  files         = merge({ for script in local.scripts : script => file("${path.module}/scripts/${script}") }, { "platform.json" = jsonencode(local.config) })
}
resource "oci_devops_deploy_pipeline" "platform" {
  for_each     = toset(["deploy", "validate"])
  project_id   = oci_devops_project.platform.id
  display_name = "${var.name}-${each.key}"
  description  = each.key == "deploy" ? "Run independent component pipelines in dependency order, then validate current cluster state. Never allocates nodes or deploys models." : "Fresh read-only platform/node validation. Does not install/upgrade components or deploy models."
  deploy_pipeline_parameters {
    dynamic "items" {
      for_each = local.parameters
      content {
        name          = items.key
        default_value = items.value
        description   = "Non-secret runtime environment setting; component settings are editable on each component pipeline."
      }
    }
  }
}
resource "oci_devops_deploy_artifact" "platform" {
  for_each                   = local.command_specs
  project_id                 = oci_devops_project.platform.id
  display_name               = "${var.name}-${each.key}-command"
  deploy_artifact_type       = "COMMAND_SPEC"
  argument_substitution_mode = "NONE"
  deploy_artifact_source {
    deploy_artifact_source_type = "INLINE"
    base64encoded_content       = base64encode(module.inline_platform[each.key].content)
  }
}
resource "oci_devops_deploy_stage" "platform" {
  for_each                        = local.command_specs
  deploy_pipeline_id              = oci_devops_deploy_pipeline.platform[each.key].id
  display_name                    = each.key == "deploy" ? "deploy-component-graph" : "validate-platform"
  deploy_stage_type               = "SHELL"
  command_spec_deploy_artifact_id = oci_devops_deploy_artifact.platform[each.key].id
  timeout_in_seconds              = 3600
  deploy_stage_predecessor_collection {
    items { id = oci_devops_deploy_pipeline.platform[each.key].id }
  }
  container_config {
    container_config_type = "CONTAINER_INSTANCE_CONFIG"
    compartment_id        = var.compartment_id
    shape_name            = "CI.Standard.E4.Flex"
    shape_config {
      ocpus         = 1
      memory_in_gbs = 8
    }
    network_channel {
      network_channel_type = "SERVICE_VNIC_CHANNEL"
      subnet_id            = var.subnet_id
      nsg_ids              = var.nsg_ids
    }
  }
}
resource "oci_identity_dynamic_group" "bootstrap" {
  provider       = oci.home
  compartment_id = var.tenancy_ocid
  name           = "${var.name}-bootstrap"
  description    = "Exact platform deployment pipeline identities."
  matching_rule  = "ANY {${join(", ", [for id in local.all_pipeline_ids : "resource.id = '${id}'"])}}"
}
resource "oci_identity_policy" "bootstrap" {
  provider       = oci.home
  compartment_id = var.tenancy_ocid
  name           = "${var.name}-bootstrap"
  description    = "Private OKE delivery, chart mirroring and Generic Artifact Registry access."
  statements = concat([
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to use cluster-family in compartment id ${var.config.target.cluster_compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to manage devops-deployment in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to read devops-family in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to manage compute-container-instances in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to manage compute-containers in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to use virtual-network-family in compartment id ${data.oci_core_subnet.runner.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to read artifact-repositories in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to read generic-artifacts in compartment id ${var.compartment_id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to use log-content in compartment id ${var.compartment_id}"
    ], try(var.config.cluster_authorization_mode, "iam") == "iam" ? [
    "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to manage clusters in compartment id ${var.config.target.cluster_compartment_id} where all {target.cluster.id = '${var.config.cluster_id}', request.permission = 'CLUSTER_MANAGE'}"
  ] : [], [for repo in values(module.components.chart_repositories) : "Allow dynamic-group id ${oci_identity_dynamic_group.bootstrap.id} to manage repos in compartment id ${var.compartment_id} where target.repo.name = '${repo.name}'"])
}
output "bootstrap_rbac" {
  value = {
    apiVersion = "rbac.authorization.k8s.io/v1", kind = "ClusterRoleBinding", metadata = { name = "${var.name}-bootstrap" },
    roleRef    = { apiGroup = "rbac.authorization.k8s.io", kind = "ClusterRole", name = "cluster-admin" },
    subjects   = [for id in local.all_pipeline_ids : { kind = "User", name = id, apiGroup = "rbac.authorization.k8s.io" }]
  }
}
output "platform" {
  value = {
    schema_version               = "2.0", platform_name = var.name, generation = local.generation, region = var.config.region, cluster_id = var.config.cluster_id,
    allocation                   = var.config.allocation, gpu_shape = var.config.gpu_shape, node_count = var.config.node_count, gpu_count_per_host = var.config.gpu_count_per_host,
    validation_scope             = try(var.config.gpu_allocation_enabled, true) ? "platform_and_gpu_capacity" : "cpu_components_only",
    gpu_selector                 = "oke-llm/allocation=${var.name}", cpu_placement = "existing_cluster_cpu_pools", cpu_budget = local.component_budget,
    project_id                   = oci_devops_project.platform.id, bootstrap_pipeline_id = oci_devops_deploy_pipeline.platform["deploy"].id,
    automatic_deployment         = { automatically_started = true, id = oci_devops_deployment.bootstrap.id, state = oci_devops_deployment.bootstrap.state, revision = local.bootstrap_revision },
    script_repository_id         = oci_artifacts_repository.scripts.id,
    component_pipeline_ids       = module.components.component_pipeline_ids, undeploy_pipeline_ids = module.components.undeploy_pipeline_ids,
    validation_pipeline_id       = oci_devops_deploy_pipeline.platform["validate"].id,
    component_generations        = module.components.generations, chart_repositories = module.components.chart_repositories,
    specification                = { delivery = "inline_command_spec", sha256 = sha256(jsonencode(local.config)), command_spec_bytes = { for mode, spec in module.inline_platform : mode => spec.byte_size } },
    evidence                     = { source = "devops_logs", log_group_id = oci_logging_log_group.platform.id, log_id = oci_logging_log.platform.id },
    required_components          = keys(local.component_specs), monitoring_enabled = local.monitoring_enabled, keda_enabled = local.keda_enabled,
    components                   = { for key, c in local.component_specs : key => { mode = c.mode, namespace = c.namespace, release_name = c.release_name, chart_version = c.chart.version, crd_names = c.crd_names, owner_name = module.components.owner_names[key], generation = module.components.generations[key], deployment_names = c.deployment_names } },
    prometheus_url               = try(local.component_specs.prometheus.mode != "retire" ? "http://llm-monitoring-kube-prom-prometheus.${local.component_specs.prometheus.namespace}.svc.cluster.local:9090" : null, null),
    cluster_authorization        = try(var.config.cluster_authorization_mode, "iam"),
    cluster_compartment_id       = var.config.target.cluster_compartment_id, kubernetes_version = var.config.target.kubernetes_version,
    deploy_environment_id        = oci_devops_deploy_environment.cluster.id, runner_subnet_id = var.subnet_id, runner_nsg_ids = var.nsg_ids,
    model_onboarding_pipeline_id = oci_devops_deploy_pipeline.model_onboarding.id,
    model_onboarding = {
      pipeline_id        = oci_devops_deploy_pipeline.model_onboarding.id, namespace_prefix = "${var.name}-model-",
      owner_label        = "oke-llm/platform-owner", owner_value = substr(sha256("${var.name}/${var.config.cluster_id}"), 0, 32),
      required_arguments = ["MODEL_NAMESPACE", "MODEL_PIPELINE_IDS", "MODEL_PROJECT_ID", "MODEL_GPU_POOL_ID"], operations = ["grant", "revoke"], automatically_started = false
    },
    runtime_readiness = "component coordinator checks are required for Apply success; model inference and GPU fabric performance remain unvalidated"
  }
}
