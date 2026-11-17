# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12" } }
}
resource "oci_ons_notification_topic" "model" {
  compartment_id = "compartment"
  name           = "legacy-model-notifications"
}
resource "oci_devops_project" "model" {
  compartment_id = "compartment"
  name           = "legacy-model"
  notification_config { topic_id = oci_ons_notification_topic.model.id }
}
output "topic_name" { value = oci_ons_notification_topic.model.name }
output "project_name" { value = oci_devops_project.model.name }

resource "oci_logging_log_group" "model" {
  compartment_id = "compartment"
  display_name   = "legacy--model"
}
output "log_group_name" { value = oci_logging_log_group.model.display_name }
