# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
  mock_data "oci_objectstorage_namespace" { defaults = { namespace = "fixture" } }
  mock_data "oci_core_subnet" { defaults = { compartment_id = "network-compartment" } }
}
mock_provider "oci" { alias = "home" }
variables {
  mode                   = "object_storage"
  name                   = "fixture"
  tenancy_ocid           = "tenancy"
  compartment_id         = "model-compartment"
  project_id             = "project"
  artifact_repository_id = "source-repository"
  cluster_id             = "cluster"
  cluster_compartment_id = "cluster-compartment"
  cluster_type           = "ENHANCED_CLUSTER"
  region                 = "eu-frankfurt-1"
  kubernetes_version     = "v1.34.1"
  subnet_id              = "runner-subnet"
  staging_image          = "registry.example/model-stager@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  cpu_node_selector      = { "node-pool" = "confirmed-cpu" }
  model = {
    id    = "owner/model", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", variant = "bf16",
    files = [for i in range(1024) : { path = "large-pinned-checkpoint-shard-${i}-of-1024.safetensors", size_bytes = 1048576 }]
  }
}
run "large_pinned_manifest_does_not_expand_the_inline_command" {
  command = plan
  assert {
    condition     = length(local.config) > 51200 && module.inline_command[0].encoded_size < 51200 && keys(oci_generic_artifacts_content_artifact_by_path.input) == ["model.json"] && length(yamldecode(output.command_spec).inputArtifacts) == 1
    error_message = "Large pinned manifests must remain one Registry input, with plan-known resource keys and bounded readable inline source delivery."
  }
}
