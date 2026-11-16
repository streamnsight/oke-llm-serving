# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
  mock_resource "oci_devops_deployment" { defaults = { state = "SUCCEEDED" } }
  mock_resource "oci_artifacts_repository" { defaults = { id = "ocid1.artifactrepository.oc1.test.fixture" } }
  mock_data "oci_objectstorage_namespace" { defaults = { namespace = "fixture" } }
  mock_data "oci_core_subnet" { defaults = { compartment_id = "network-compartment", ipv6cidr_block = "", ipv6cidr_blocks = [] } }
}
mock_provider "oci" { alias = "home" }
variables {
  tenancy_ocid   = "root"
  compartment_id = "platform-compartment"
  name           = "fixture"
  subnet_id      = "runner"
  nsg_ids        = ["runner-nsg"]
  config = {
    platform_name = "fixture", region = "us-ashburn-1", cluster_id = "cluster", gpu_shape = "BM.GPU.A10.4", node_count = 1, gpu_count_per_host = 4,
    cpu_placement = "existing_cluster_cpu_pools", target = { cluster_compartment_id = "cluster-compartment", kubernetes_version = "v1.34.1" },
    allocation    = { gpu_pool_id = "gpu-pool", compute_cluster_id = null, allocation_identity = "pool-identity" }
  }
}

run "default_platform_installs_monitoring_and_shared_KEDA_without_model_scaling" {
  command = apply
  assert {
    condition     = output.platform.schema_version == "2.0" && output.platform.required_components == ["keda", "prometheus"] && output.platform.monitoring_enabled && output.platform.keda_enabled && keys(output.platform.component_pipeline_ids) == ["keda", "prometheus"] && keys(output.platform.undeploy_pipeline_ids) == ["keda", "prometheus"] && keys(output.platform.chart_repositories) == ["keda", "prometheus"]
    error_message = "Monitoring and shared KEDA default on; installing KEDA supplies no per-model autoscaling policy, and single-node serving does not require LWS."
  }
  assert {
    condition     = output.platform.cpu_placement == "existing_cluster_cpu_pools" && !output.platform.cpu_budget.creates_cpu_pool && !contains(keys(output.platform.allocation), "cpu_pool_id") && !contains(keys(output.platform), "readiness_uri") && strcontains(output.platform.runtime_readiness, "required for Apply success") && output.platform.automatic_deployment.automatically_started && output.platform.automatic_deployment.state == "SUCCEEDED"
    error_message = "The v2 descriptor uses existing CPU pools and waits for automatic validation, without creating CPU nodes."
  }
  assert {
    condition     = oci_artifacts_repository.scripts.is_immutable && !contains(keys(output.platform), "result_repository_id") && output.platform.specification.delivery == "inline_command_spec" && output.platform.specification.sha256 == sha256(jsonencode(local.config)) && output.platform.evidence.source == "devops_logs" && output.platform.evidence.log_id == oci_logging_log.platform.id
    error_message = "Desired configuration is delivered inline and routine execution reports belong in DevOps logs, without a results repository."
  }
  assert {
    condition     = alltrue([for mode, spec in module.inline_platform : spec.byte_size <= 51200 && strcontains(spec.preparation_command, "platform.sh") && strcontains(spec.preparation_command, "platform.json") && oci_devops_deploy_artifact.platform[mode].deploy_artifact_source[0].base64encoded_content == spec.content]) && alltrue([for spec in values(local.command_specs) : length(yamldecode(spec).inputArtifacts) == 0 && strcontains(yamldecode(spec).steps[0].command, "sha256sum -c -") && !strcontains(spec, "base64")])
    error_message = "Platform code and configuration must remain readable inline heredocs with exact checksums, bounded payloads and no runtime base64 decoding."
  }
  assert {
    condition     = alltrue([for stage in oci_devops_deploy_stage.platform : stage.deploy_stage_type == "SHELL" && stage.container_config[0].network_channel[0].subnet_id == "runner"]) && alltrue([for artifact in oci_devops_deploy_artifact.platform : artifact.argument_substitution_mode == "NONE"]) && yamldecode(local.command_specs.deploy).env.variables.REGION == "$${REGION}" && yamldecode(local.command_specs.validate).env.variables.PLATFORM_MODE == "validate" && alltrue([for spec in values(local.command_specs) : strcontains(yamldecode(spec).steps[0].command, "export REGION CLUSTER_ID PLATFORM_NAME")])
    error_message = "Separate orchestration/readiness Shell stages must export editable native environment settings and use the private runner subnet."
  }
  assert {
    condition     = oci_devops_deploy_environment.cluster.deploy_environment_type == "OKE_CLUSTER" && oci_devops_deploy_environment.cluster.cluster_id == "cluster" && oci_devops_deploy_environment.cluster.network_channel[0].network_channel_type == "PRIVATE_ENDPOINT_CHANNEL" && oci_devops_deploy_environment.cluster.network_channel[0].subnet_id == "runner" && toset(oci_devops_deploy_environment.cluster.network_channel[0].nsg_ids) == toset(["runner-nsg"])
    error_message = "Native chart stages need the selected private OKE environment and matching runner networking."
  }
  assert {
    condition     = length(output.bootstrap_rbac.subjects) == 7 && contains([for subject in output.bootstrap_rbac.subjects : subject.name], output.platform.bootstrap_pipeline_id) && contains([for subject in output.bootstrap_rbac.subjects : subject.name], output.platform.validation_pipeline_id) && contains([for subject in output.bootstrap_rbac.subjects : subject.name], output.platform.component_pipeline_ids.prometheus) && contains([for subject in output.bootstrap_rbac.subjects : subject.name], output.platform.undeploy_pipeline_ids.prometheus) && output.bootstrap_rbac.roleRef.name == "cluster-admin"
    error_message = "Only the actual orchestration, validation, component deployment and teardown pipeline principals receive Kubernetes authorization."
  }
  assert {
    condition     = anytrue([for rule in oci_identity_policy.bootstrap.statements : strcontains(rule, "to manage compute-containers in compartment id platform-compartment")]) && anytrue([for rule in oci_identity_policy.bootstrap.statements : strcontains(rule, "to manage compute-container-instances in compartment id platform-compartment")]) && anytrue([for rule in oci_identity_policy.bootstrap.statements : strcontains(rule, "to use virtual-network-family in compartment id network-compartment")]) && alltrue([for rule in oci_identity_policy.bootstrap.statements : !strcontains(rule, "object-family") && !strcontains(rule, "manage generic-artifacts")])
    error_message = "Shell execution needs both Container Instance permissions, scoped private-network access and no pipeline artifact-bucket policy."
  }
}

run "lws_and_disaggregated_set_are_selected_explicitly" {
  command = apply
  variables { config = merge(var.config, { enable_lws = true, enable_disaggregated_set = true }) }
  assert {
    condition     = output.platform.required_components == ["keda", "lws", "prometheus"] && keys(output.platform.component_pipeline_ids) == ["keda", "lws", "prometheus"] && keys(output.platform.undeploy_pipeline_ids) == ["keda", "lws", "prometheus"] && keys(output.platform.chart_repositories) == ["keda", "lws", "prometheus"] && yamldecode(local.component_specs.lws.values_yaml).enableDisaggregatedSet && contains(local.component_specs.lws.crd_names, "disaggregatedsets.disaggregatedset.x-k8s.io") && contains(local.component_specs.lws.crd_names, "disaggregatedsetrolescalers.disaggregatedset.x-k8s.io")
    error_message = "A selected distributed topology gets its own LWS deployment/teardown and correct DisaggregatedSet API groups."
  }
  assert {
    condition     = yamldecode(local.component_specs.lws.values_yaml).resources.requests.cpu == "$${CONTROLLER_CPU}" && yamldecode(local.component_specs.prometheus.values_yaml).prometheus.prometheusSpec.resources.requests.cpu == "$${PROMETHEUS_CPU}" && yamldecode(local.component_specs.prometheus.values_yaml).prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage == "$${PROMETHEUS_STORAGE}" && local.component_specs.lws.parameters.CONTROLLER_CPU == "1"
    error_message = "Chart values retain editable runtime placeholders instead of baking per-run settings into scripts."
  }
}

run "KEDA_controller_installation_is_independent_of_monitoring_and_model_policy" {
  command = apply
  variables { config = merge(var.config, { monitoring_enabled = false, keda_enabled = true }) }
  assert {
    condition     = !output.platform.monitoring_enabled && output.platform.keda_enabled && output.platform.required_components == ["keda"] && keys(output.platform.component_pipeline_ids) == ["keda"] && length(local.component_specs.keda.dependencies) == 0 && local.component_specs.keda.parameters.OPERATOR_CPU == "100m" && yamldecode(local.component_specs.keda.values_yaml).resources.operator.requests.cpu == "$${OPERATOR_CPU}"
    error_message = "Installing the KEDA controller alone neither installs Prometheus nor enables model autoscaling; its settings remain editable."
  }
}

run "all_optional_components_can_be_disabled" {
  command = apply
  variables { config = merge(var.config, { monitoring_enabled = false, keda_enabled = false, enable_lws = false }) }
  assert {
    condition     = length(output.platform.required_components) == 0 && length(output.platform.component_pipeline_ids) == 0 && length(output.platform.undeploy_pipeline_ids) == 0 && length(output.platform.chart_repositories) == 0 && length(output.bootstrap_rbac.subjects) == 3 && output.platform.cpu_budget.cpu_requests_millicores == 0 && output.platform.cpu_budget.persistent_volume_gib == 0
    error_message = "An all-off platform keeps only its orchestration/validation entry points and creates no component pipelines, chart repositories or CPU/storage request budget."
  }
}

run "external_monitoring_is_reused_without_teardown_or_chart_mirroring" {
  command = apply
  variables { config = merge(var.config, { keda_enabled = false, component_modes = { prometheus = "reuse" } }) }
  assert {
    condition     = local.component_specs.prometheus.mode == "reuse" && keys(output.platform.component_pipeline_ids) == ["prometheus"] && length(output.platform.undeploy_pipeline_ids) == 0 && length(output.platform.chart_repositories) == 0 && length(output.bootstrap_rbac.subjects) == 4 && local.config.components.prometheus.mode == "reuse"
    error_message = "Reusing an existing controller gets a validation pipeline but neither native Helm ownership/mirroring nor an uninstall pipeline."
  }
}

run "retire_keeps_only_an_explicit_teardown_pipeline" {
  command = apply
  variables { config = merge(var.config, { monitoring_enabled = false, keda_enabled = false, component_modes = { prometheus = "retire" } }) }
  assert {
    condition     = local.component_specs.prometheus.mode == "retire" && length(output.platform.component_pipeline_ids) == 0 && keys(output.platform.undeploy_pipeline_ids) == ["prometheus"] && length(output.platform.chart_repositories) == 0 && length(output.bootstrap_rbac.subjects) == 4 && local.config.components.prometheus.pipeline_id == null
    error_message = "Retiring a component preserves its explicit teardown path without leaving a deploy pipeline or new chart mirror."
  }
}

run "private_oke_environment_rejects_ipv6_enabled_runner_subnets" {
  command = plan
  override_data {
    target = data.oci_core_subnet.runner
    values = { compartment_id = "network-compartment", ipv6cidr_block = "2001:db8::/64", ipv6cidr_blocks = ["2001:db8::/64"] }
  }
  expect_failures = [oci_devops_deploy_environment.cluster]
}
run "kubernetes_iam_permission_is_scoped_without_nodepool_management" {
  command = plan
  assert {
    condition     = length([for rule in oci_identity_policy.bootstrap.statements : rule if strcontains(rule, "request.permission = 'CLUSTER_MANAGE'") && strcontains(rule, "target.cluster.id = 'cluster'")]) == 1 && alltrue([for rule in oci_identity_policy.bootstrap.statements : !strcontains(rule, "manage cluster-family") && !strcontains(rule, "manage cluster-node-pools")])
    error_message = "Automatic Kubernetes administration must be constrained to this cluster and CLUSTER_MANAGE, excluding OCI infrastructure changes."
  }
}
run "explicit_rbac_mode_omits_kubernetes_iam_administration" {
  command = plan
  variables { config = merge(var.config, { cluster_authorization_mode = "rbac" }) }
  assert {
    condition     = alltrue([for rule in oci_identity_policy.bootstrap.statements : !strcontains(rule, "CLUSTER_MANAGE")]) && output.platform.cluster_authorization == "rbac" && length(output.bootstrap_rbac.subjects) > 0
    error_message = "RBAC mode must retain explicit binding output without granting IAM Kubernetes administration."
  }
}
run "trusted_model_onboarding_is_separate_and_binding_is_complete" {
  command = apply
  assert {
    condition     = output.platform.deploy_environment_id == oci_devops_deploy_environment.cluster.id && output.platform.runner_subnet_id == "runner" && toset(output.platform.runner_nsg_ids) == toset(["runner-nsg"]) && output.platform.kubernetes_version == "v1.34.1" && output.platform.cluster_compartment_id == "cluster-compartment"
    error_message = "The generated model bundle must reference the existing private OKE environment, project and runner network."
  }
  assert {
    condition     = output.platform.model_onboarding_pipeline_id == oci_devops_deploy_pipeline.model_onboarding.id && contains([for subject in output.bootstrap_rbac.subjects : subject.name], oci_devops_deploy_pipeline.model_onboarding.id) && output.platform.model_onboarding.namespace_prefix == "fixture-model-" && output.platform.model_onboarding.owner_value == substr(sha256("fixture/cluster"), 0, 32) && !output.platform.model_onboarding.automatically_started
    error_message = "Only the trusted platform principal onboards exact model principals; no model pipeline starts automatically."
  }
  assert {
    condition     = oci_devops_deploy_stage.model_onboarding.deploy_stage_type == "SHELL" && oci_devops_deploy_artifact.model_onboarding.argument_substitution_mode == "NONE" && oci_devops_deploy_artifact.model_onboarding.deploy_artifact_source[0].deploy_artifact_source_type == "INLINE" && oci_devops_deploy_artifact.model_onboarding.deploy_artifact_source[0].base64encoded_content == module.inline_onboarding.content && module.inline_onboarding.byte_size <= 51200 && length(yamldecode(local.model_onboarding_command).inputArtifacts) == 0 && yamldecode(local.model_onboarding_command).env.variables.MODEL_NAMESPACE == "$${MODEL_NAMESPACE}" && !strcontains(local.model_onboarding_command, "base64")
    error_message = "Onboarding uses editable non-secret arguments and verified readable inline sources, with no runtime encoded code."
  }
}

run "DisaggregatedSet_selects_its_required_LWS_controller" {
  command = apply
  variables { config = merge(var.config, { monitoring_enabled = false, keda_enabled = false, enable_lws = false, enable_disaggregated_set = true }) }
  assert {
    condition     = var.config.node_count == 1 && var.config.gpu_count_per_host == 4 && output.platform.required_components == ["lws"] && local.config.enable_lws && yamldecode(local.component_specs.lws.values_yaml).enableDisaggregatedSet
    error_message = "DisaggregatedSet on one multi-GPU node still needs LWS, regardless of the plain LWS switch."
  }
}
run "shared_KEDA_can_be_reused_without_creating_a_second_release" {
  command = apply
  variables { config = merge(var.config, { monitoring_enabled = false, keda_enabled = true, component_modes = { keda = "reuse" } }) }
  assert {
    condition     = output.platform.keda_enabled && keys(output.platform.component_pipeline_ids) == ["keda"] && length(output.platform.undeploy_pipeline_ids) == 0 && length(output.platform.chart_repositories) == 0 && local.component_specs.keda.mode == "reuse"
    error_message = "Existing KEDA receives a validation pipeline, not a second install, chart mirror or uninstall owner."
  }
}

run "unchanged_component_revision_does_not_rerun_for_inventory_observations" {
  command = plan
  variables {
    config = merge(var.config, { target = merge(var.config.target, { oke_addons = [{ name = "NodeFeatureDiscovery", state = "ACTIVE" }], gpu_image = { id = "newly-observed-image" } }), allocation = merge(var.config.allocation, { capacity = { observed_at = "later", available_hosts = 17 }, oke_addons = [{ name = "NodeFeatureDiscovery", state = "ACTIVE" }], retained_nodes = 1, additional_nodes = 0 }) })
  }
  assert {
    condition     = local.bootstrap_revision == run.default_platform_installs_monitoring_and_shared_KEDA_without_model_scaling.platform.automatic_deployment.revision
    error_message = "Read-only capacity/add-on/image observations and retained-node counts must not rerun unchanged controllers."
  }
  assert {
    condition     = !oci_devops_deployment.bootstrap.trigger_new_devops_deployment && oci_devops_deployment.bootstrap.deployment_type == "PIPELINE_DEPLOYMENT"
    error_message = "Apply starts a native pipeline execution with success waiting, without an every-Apply trigger."
  }
}
run "gpu_pool_change_requires_a_new_automatic_revision" {
  command = plan
  variables { config = merge(var.config, { allocation = merge(var.config.allocation, { gpu_pool_id = "replacement-gpu-pool" }) }) }
  assert {
    condition     = local.bootstrap_revision != run.default_platform_installs_monitoring_and_shared_KEDA_without_model_scaling.platform.automatic_deployment.revision
    error_message = "A changed GPU allocation binding must rerun readiness against the selected pool."
  }
}
run "component_change_requires_a_new_automatic_revision" {
  command = plan
  variables { config = merge(var.config, { enable_lws = true }) }
  assert {
    condition     = local.bootstrap_revision != run.default_platform_installs_monitoring_and_shared_KEDA_without_model_scaling.platform.automatic_deployment.revision
    error_message = "Changing the selected component graph must rerun the coordinator."
  }
}
run "failed_coordinator_cannot_make_apply_succeed" {
  command = apply
  variables { config = merge(var.config, { enable_lws = true, monitoring_enabled = false }) }
  override_resource {
    target = oci_devops_deployment.bootstrap
    values = { state = "FAILED" }
  }
  expect_failures = [oci_devops_deployment.bootstrap]
}
