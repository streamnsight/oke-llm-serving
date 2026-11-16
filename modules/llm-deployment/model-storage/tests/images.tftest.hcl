# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {}
mock_provider "oci" { alias = "home" }
run "missing_stager_remains_unknown" {
  command = plan
  assert {
    condition     = local.staging_image == null && local.parameters.STAGING_IMAGE == "unset" && output.storage.staging_image == null
    error_message = "An optional unset stager must remain unset, without inventing an image."
  }
}
run "single_name_uses_docker_hub_library" {
  command = plan
  variables { staging_image = "model-stager@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  assert {
    condition     = local.parameters.STAGING_IMAGE == "docker.io/library/${var.staging_image}"
    error_message = "Single-component Docker Hub names must include their registry and library namespace."
  }
}
run "docker_hub_organization_is_qualified" {
  command = plan
  variables { staging_image = "example/model-stager:v1@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  assert {
    condition     = local.parameters.STAGING_IMAGE == "docker.io/${var.staging_image}"
    error_message = "Organization references must acquire only docker.io, preserving their repository, tag and digest."
  }
}
run "private_registry_is_preserved" {
  command = plan
  variables { staging_image = "private.example/team/model-stager@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  assert {
    condition     = local.parameters.STAGING_IMAGE == var.staging_image
    error_message = "An explicit private registry must not be redirected to Docker Hub."
  }
}
run "ocir_is_preserved" {
  command = plan
  variables { staging_image = "ca-montreal-1.ocir.io/tenancy/model-stager@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  assert {
    condition     = local.parameters.STAGING_IMAGE == var.staging_image
    error_message = "OCI Registry addresses and digests must be preserved."
  }
}
run "ghcr_is_preserved" {
  command = plan
  variables { staging_image = "ghcr.io/team/model-stager@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  assert {
    condition     = local.parameters.STAGING_IMAGE == var.staging_image
    error_message = "GitHub Container Registry addresses and digests must be preserved."
  }
}
run "localhost_with_port_is_preserved" {
  command = plan
  variables { staging_image = "localhost:5000/model-stager@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  assert {
    condition     = local.parameters.STAGING_IMAGE == var.staging_image
    error_message = "An explicit localhost registry port must not be redirected."
  }
}
