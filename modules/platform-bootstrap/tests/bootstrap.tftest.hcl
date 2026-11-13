# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {}
mock_provider "oci" { alias = "home" }
variables {
  tenancy_ocid   = "root"
  compartment_id = "platform-compartment"
  name           = "fixture"
  subnet_id      = "runner"
  config = {
    platform_name = "fixture", region = "us-ashburn-1", cluster_id = "cluster", gpu_shape = "BM.GPU.A10.4", node_count = 1, gpu_count_per_host = 4,
    cpu_placement = "existing_cluster_cpu_pools", target = { cluster_compartment_id = "cluster-compartment", kubernetes_version = "v1.34.1" },
    allocation    = { gpu_pool_id = "gpu-pool", compute_cluster_id = null, allocation_identity = "pool-identity" }
  }
}
run "platform_has_explicit_shell_bootstrap_and_separate_readiness" {
  command = apply
  assert {
    condition     = oci_devops_deploy_stage.bootstrap.deploy_stage_type == "SHELL" && oci_devops_deploy_artifact.bootstrap.argument_substitution_mode == "NONE" && yamldecode(local.command_spec).failImmediatelyOnError
    error_message = "Use the explicit Shell command-spec pattern without evaluating frozen data as placeholder source."
  }
  assert {
    condition     = output.bootstrap_rbac.subjects[0].name == output.platform.bootstrap_pipeline_id && output.bootstrap_rbac.roleRef.name == "cluster-admin"
    error_message = "Shared CRD installation requires explicit administrator bootstrap for this one principal."
  }
  assert {
    condition     = jsondecode(oci_objectstorage_object.specification.content).generation == output.platform.generation && oci_objectstorage_object.specification.object == "fixture/platform-spec.json" && endswith(output.platform.readiness_uri, "${output.platform.generation}/readiness.json") && output.platform.cpu_placement == "existing_cluster_cpu_pools"
    error_message = "Terraform owns desired specification; pipeline readiness must have a separate generation-specific object."
  }
  assert {
    condition     = oci_objectstorage_bucket.platform.access_type == "NoPublicAccess" && !contains(keys(output.platform.allocation), "cpu_pool_id")
    error_message = "The platform descriptor must stay private and refer only to GPU infrastructure."
  }
}
