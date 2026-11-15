# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
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

run "default_platform_only_requires_monitoring" {
  command = apply
  assert {
    condition     = output.platform.schema_version == "2.0" && output.platform.required_components == ["prometheus"] && output.platform.monitoring_enabled && !output.platform.autoscaling_enabled && keys(output.platform.component_pipeline_ids) == ["prometheus"] && keys(output.platform.undeploy_pipeline_ids) == ["prometheus"] && keys(output.platform.chart_repositories) == ["prometheus"]
    error_message = "Monitoring defaults on; LWS and KEDA must not acquire pipelines or chart repositories without a selected requirement."
  }
  assert {
    condition     = output.platform.cpu_placement == "existing_cluster_cpu_pools" && !output.platform.cpu_budget.creates_cpu_pool && !contains(keys(output.platform.allocation), "cpu_pool_id") && !contains(keys(output.platform), "readiness_uri") && output.platform.runtime_readiness == "not_asserted_by_terraform; run deploy/validate and inspect immutable execution evidence"
    error_message = "The v2 descriptor uses existing CPU pools and immutable Artifact Registry evidence, without claiming live readiness or creating CPU nodes."
  }
  assert {
    condition     = oci_artifacts_repository.scripts.is_immutable && oci_artifacts_repository.results.is_immutable && output.platform.specification.repository_id == oci_artifacts_repository.scripts.id && output.platform.evidence.repository_id == oci_artifacts_repository.results.id && oci_generic_artifacts_content_artifact_by_path.specification.version == sha256(oci_generic_artifacts_content_artifact_by_path.specification.content) && jsondecode(oci_generic_artifacts_content_artifact_by_path.specification.content).generation == output.platform.generation
    error_message = "Desired platform configuration and immutable run reports belong in separate Artifact Registry repositories, with content-addressed specification versions."
  }
  assert {
    condition     = length(oci_generic_artifacts_content_artifact_by_path.script) == 2 && alltrue([for script, artifact in oci_generic_artifacts_content_artifact_by_path.script : artifact.content == file("${path.module}/scripts/${script}") && artifact.version == filesha256("${path.module}/scripts/${script}")]) && alltrue([for spec in values(local.command_specs) : length(yamldecode(spec).inputArtifacts) == 3 && alltrue([for artifact in yamldecode(spec).inputArtifacts : artifact.type == "GENERIC_ARTIFACT" && artifact.registryId == oci_artifacts_repository.scripts.id]) && strcontains(yamldecode(spec).steps[0].command, "sha256sum -c -") && !strcontains(spec, "base64") && !strcontains(spec, "os object get")])
    error_message = "Platform code and configuration must be verified file inputs from immutable Artifact Registry, not encoded scripts or Object Storage downloads."
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
    condition     = length(output.bootstrap_rbac.subjects) == 5 && contains([for subject in output.bootstrap_rbac.subjects : subject.name], output.platform.bootstrap_pipeline_id) && contains([for subject in output.bootstrap_rbac.subjects : subject.name], output.platform.validation_pipeline_id) && contains([for subject in output.bootstrap_rbac.subjects : subject.name], output.platform.component_pipeline_ids.prometheus) && contains([for subject in output.bootstrap_rbac.subjects : subject.name], output.platform.undeploy_pipeline_ids.prometheus) && output.bootstrap_rbac.roleRef.name == "cluster-admin"
    error_message = "Only the actual orchestration, validation, component deployment and teardown pipeline principals receive Kubernetes authorization."
  }
  assert {
    condition     = anytrue([for rule in oci_identity_policy.bootstrap.statements : strcontains(rule, "to manage compute-containers in compartment id platform-compartment")]) && anytrue([for rule in oci_identity_policy.bootstrap.statements : strcontains(rule, "to manage compute-container-instances in compartment id platform-compartment")]) && anytrue([for rule in oci_identity_policy.bootstrap.statements : strcontains(rule, "to use virtual-network-family in compartment id network-compartment")]) && alltrue([for rule in oci_identity_policy.bootstrap.statements : !strcontains(rule, "object-family")])
    error_message = "Shell execution needs both Container Instance permissions, scoped private-network access and no pipeline artifact-bucket policy."
  }
}

run "lws_and_disaggregated_set_are_selected_explicitly" {
  command = apply
  variables { config = merge(var.config, { enable_lws = true, enable_disaggregated_set = true }) }
  assert {
    condition     = output.platform.required_components == ["lws", "prometheus"] && keys(output.platform.component_pipeline_ids) == ["lws", "prometheus"] && keys(output.platform.undeploy_pipeline_ids) == ["lws", "prometheus"] && keys(output.platform.chart_repositories) == ["lws", "prometheus"] && yamldecode(local.component_specs.lws.values_yaml).enableDisaggregatedSet && contains(local.component_specs.lws.crd_names, "disaggregatedsets.disaggregatedset.x-k8s.io") && contains(local.component_specs.lws.crd_names, "disaggregatedsetrolescalers.disaggregatedset.x-k8s.io")
    error_message = "A selected distributed topology gets its own LWS deployment/teardown and correct DisaggregatedSet API groups."
  }
  assert {
    condition     = yamldecode(local.component_specs.lws.values_yaml).resources.requests.cpu == "$${CONTROLLER_CPU}" && yamldecode(local.component_specs.prometheus.values_yaml).prometheus.prometheusSpec.resources.requests.cpu == "$${PROMETHEUS_CPU}" && yamldecode(local.component_specs.prometheus.values_yaml).prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage == "$${PROMETHEUS_STORAGE}" && local.component_specs.lws.parameters.CONTROLLER_CPU == "1"
    error_message = "Chart values retain editable runtime placeholders instead of baking per-run settings into scripts."
  }
}

run "keda_is_opt_in_and_its_operators_can_install_independently" {
  command = apply
  variables { config = merge(var.config, { monitoring_enabled = false, autoscaling_enabled = true }) }
  assert {
    condition     = !output.platform.monitoring_enabled && output.platform.autoscaling_enabled && output.platform.required_components == ["keda", "prometheus"] && keys(output.platform.component_pipeline_ids) == ["keda", "prometheus"] && length(local.component_specs.keda.dependencies) == 0 && local.component_specs.keda.parameters.OPERATOR_CPU == "100m" && yamldecode(local.component_specs.keda.values_yaml).resources.operator.requests.cpu == "$${OPERATOR_CPU}"
    error_message = "Opt-in autoscaling needs Prometheus metrics even with monitoring off; operator installations remain independent and their settings editable."
  }
}

run "all_optional_components_can_be_disabled" {
  command = apply
  variables { config = merge(var.config, { monitoring_enabled = false, autoscaling_enabled = false, enable_lws = false }) }
  assert {
    condition     = length(output.platform.required_components) == 0 && length(output.platform.component_pipeline_ids) == 0 && length(output.platform.undeploy_pipeline_ids) == 0 && length(output.platform.chart_repositories) == 0 && length(output.bootstrap_rbac.subjects) == 3 && output.platform.cpu_budget.cpu_requests_millicores == 0 && output.platform.cpu_budget.persistent_volume_gib == 0
    error_message = "An all-off platform keeps only its orchestration/validation entry points and creates no component pipelines, chart repositories or CPU/storage request budget."
  }
}

run "external_monitoring_is_reused_without_teardown_or_chart_mirroring" {
  command = apply
  variables { config = merge(var.config, { component_modes = { prometheus = "reuse" } }) }
  assert {
    condition     = local.component_specs.prometheus.mode == "reuse" && keys(output.platform.component_pipeline_ids) == ["prometheus"] && length(output.platform.undeploy_pipeline_ids) == 0 && length(output.platform.chart_repositories) == 0 && length(output.bootstrap_rbac.subjects) == 4 && jsondecode(oci_generic_artifacts_content_artifact_by_path.specification.content).components.prometheus.mode == "reuse"
    error_message = "Reusing an existing controller gets a validation pipeline but neither native Helm ownership/mirroring nor an uninstall pipeline."
  }
}

run "retire_keeps_only_an_explicit_teardown_pipeline" {
  command = apply
  variables { config = merge(var.config, { monitoring_enabled = false, component_modes = { prometheus = "retire" } }) }
  assert {
    condition     = local.component_specs.prometheus.mode == "retire" && length(output.platform.component_pipeline_ids) == 0 && keys(output.platform.undeploy_pipeline_ids) == ["prometheus"] && length(output.platform.chart_repositories) == 0 && length(output.bootstrap_rbac.subjects) == 4 && jsondecode(oci_generic_artifacts_content_artifact_by_path.specification.content).components.prometheus.pipeline_id == null
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
    condition     = oci_devops_deploy_stage.model_onboarding.deploy_stage_type == "SHELL" && oci_devops_deploy_artifact.model_onboarding.argument_substitution_mode == "NONE" && oci_devops_deploy_artifact.model_onboarding.deploy_artifact_source[0].deploy_artifact_source_type == "GENERIC_ARTIFACT" && oci_generic_artifacts_content_artifact_by_path.model_onboarding_command.version == sha256(local.model_onboarding_command) && length(yamldecode(local.model_onboarding_command).inputArtifacts) == 3 && yamldecode(local.model_onboarding_command).env.variables.MODEL_NAMESPACE == "$${MODEL_NAMESPACE}" && local.model_onboarding_parameters.MODEL_PIPELINE_IDS == "[]" && !strcontains(local.model_onboarding_command, "base64")
    error_message = "Onboarding uses editable non-secret arguments and verified Generic Artifact script files, never arbitrary manifests or inline encoded code."
  }
}
