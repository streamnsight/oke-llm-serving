# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
  mock_data "oci_objectstorage_namespace" { defaults = { namespace = "fixture" } }
}
variables {
  project_id                    = "project"
  compartment_id                = "compartment"
  cluster_deploy_environment_id = "oke-environment"
  cluster_id                    = "cluster"
  region                        = "eu-frankfurt-1"
  subnet_id                     = "subnet"
  name                          = "fixture"
  source_repository_id          = "source"
  result_repository_id          = "results"
  components = {
    lws = {
      mode        = "managed", namespace = "lws-system", release_name = "lws", ownership_token = "stable-platform-owner"
      chart       = { repository = "oci://registry.k8s.io/lws/charts", name = "lws", version = "1.0.0" }
      values_yaml = "replicaCount: $${REPLICAS}\n"
      parameters  = { REPLICAS = "2" }
    }
    metrics = {
      mode        = "managed", namespace = "monitoring", release_name = "metrics", ownership_token = "stable-platform-owner"
      chart       = { repository = "https://prometheus-community.github.io/helm-charts", name = "kube-prometheus-stack", version = "80.0.0" }
      values_yaml = "prometheus:\n  prometheusSpec:\n    retention: 7d\n"
    }
    external = {
      mode  = "reuse", namespace = "external", release_name = "external", ownership_token = "stable-platform-owner"
      chart = { repository = "https://example.org/charts", name = "external", version = "1.0.0" }
    }
    old = {
      mode  = "retire", namespace = "old", release_name = "old", ownership_token = "stable-platform-owner"
      chart = { repository = "https://example.org/charts", name = "old", version = "1.0.0" }
    }
  }
}
run "conditional_native_helm_delivery" {
  command = apply
  assert {
    condition     = length(oci_devops_deploy_stage.helm) == 2 && length(output.component_pipeline_ids) == 3 && length(output.undeploy_pipeline_ids) == 3 && length(output.all_pipeline_ids) == 6
    error_message = "Only managed components get native Helm; reuse cannot uninstall and retire retains teardown only."
  }
  assert {
    condition     = alltrue([for stage in values(oci_devops_deploy_stage.helm) : stage.deploy_stage_type == "OKE_HELM_CHART_DEPLOYMENT" && stage.purpose == "EXECUTE_HELM_UPGRADE" && !stage.is_uninstall_on_stage_delete && !stage.should_not_wait])
    error_message = "Charts must use bounded, waiting native Helm stages without delete-triggered uninstall."
  }
  assert {
    condition     = oci_devops_deploy_artifact.chart["lws"].deploy_artifact_source[0].deploy_artifact_version == "$${CHART_VERSION}" && oci_devops_deploy_artifact.values["lws"].argument_substitution_mode == "SUBSTITUTE_PLACEHOLDERS" && oci_devops_deploy_artifact.values["lws"].deploy_artifact_type == "GENERIC_FILE"
    error_message = "Editable chart versions and values placeholders must reach native Helm."
  }
  assert {
    condition     = alltrue([for spec in values(local.command_specs) : strcontains(yamldecode(spec).steps[0].command, "export ") && strcontains(yamldecode(spec).steps[0].command, "sha256sum -c -") && length(yamldecode(spec).inputArtifacts) == 5]) && alltrue([for artifact in values(oci_devops_deploy_artifact.command) : artifact.deploy_artifact_source[0].deploy_artifact_source_type == "GENERIC_ARTIFACT"])
    error_message = "Command specifications and verified file inputs must use Artifact Registry with exported editable parameters."
  }
  assert {
    condition     = yamldecode(local.command_specs["lws/deploy"]).env.variables.REPLICAS == "$${REPLICAS}" && yamldecode(local.command_specs["external/deploy"]).env.variables.DELIVERY_OPERATION == "reuse" && yamldecode(local.command_specs["old/undeploy"]).env.variables.DELIVERY_OPERATION == "undeploy" && yamldecode(local.command_specs["lws/deploy"]).env.variables.DELIVERY_DEPLOYMENT_ID == "$${OCI_DEPLOYMENT_ID}"
    error_message = "Lifecycle behavior must come from the declaration, not an override that leaves a mutating stage behind."
  }
  assert {
    condition     = alltrue(flatten([for parameters in values(local.parameters) : [for name in keys(parameters) : !startswith(name, "OCI_")]])) && alltrue([for parameters in values(local.parameters) : parameters.ENFORCE_HELM_DEPLOYMENT == "true" && parameters.RECOVER_LOCK_HOLDER == "none"])
    error_message = "OCI service-reserved controls cannot be declared as pipeline parameters. Prepare creates namespaces; retain the documented non-reserved Helm rerun argument."
  }
}
