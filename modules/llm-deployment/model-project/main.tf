# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12" } }
}
variable "name" { type = string }
variable "compartment_id" { type = string }
variable "target" { type = any }
locals {
  # DNS-compatible model names can contain consecutive dashes; OCI service names cannot.
  service_name = replace(var.name, "/-+/", "-")
}
resource "oci_ons_notification_topic" "model" {
  compartment_id = var.compartment_id
  name           = "${local.service_name}-notifications"
}
resource "oci_devops_project" "model" {
  compartment_id = var.compartment_id
  name           = local.service_name
  description    = "Independent model lifecycle: deploy, validate, benchmark and undeploy on separately retained GPU infrastructure."
  notification_config { topic_id = oci_ons_notification_topic.model.id }
  lifecycle {
    precondition {
      condition     = var.target.metadata_ready
      error_message = "Model target metadata failed: ${join("; ", var.target.issues)}"
    }
  }
}
resource "oci_logging_log_group" "model" {
  compartment_id = var.compartment_id
  display_name   = var.name
}
resource "oci_logging_log" "model" {
  display_name = var.name
  log_group_id = oci_logging_log_group.model.id
  log_type     = "SERVICE"
  is_enabled   = true
  configuration {
    compartment_id = var.compartment_id
    source {
      category    = "all"
      resource    = oci_devops_project.model.id
      service     = "devops"
      source_type = "OCISERVICE"
    }
  }
}
resource "oci_artifacts_repository" "scripts" {
  compartment_id  = var.compartment_id
  display_name    = "${var.name}-scripts"
  description     = "Immutable model pipeline scripts, chart inputs and frozen specifications; no model weights."
  repository_type = "GENERIC"
  is_immutable    = true
}
resource "oci_artifacts_repository" "results" {
  compartment_id  = var.compartment_id
  display_name    = "${var.name}-results"
  description     = "Immutable validation and benchmark results for this independent model project."
  repository_type = "GENERIC"
  is_immutable    = true
}
resource "oci_devops_deploy_environment" "model" {
  project_id              = oci_devops_project.model.id
  display_name            = "${var.name}-oke"
  deploy_environment_type = "OKE_CLUSTER"
  cluster_id              = var.target.cluster_id
  network_channel {
    network_channel_type = "PRIVATE_ENDPOINT_CHANNEL"
    subnet_id            = var.target.runner_subnet_id
    nsg_ids              = var.target.runner_nsg_ids
  }
}
output "resources" {
  value = {
    project_id            = oci_devops_project.model.id, project_name = oci_devops_project.model.name,
    deploy_environment_id = oci_devops_deploy_environment.model.id, compartment_id = var.compartment_id,
    script_repository_id  = oci_artifacts_repository.scripts.id, result_repository_id = oci_artifacts_repository.results.id,
    log_group_id          = oci_logging_log_group.model.id
  }
}
