# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Copied into an extracted, actually rendered ZIP by the development checker.
mock_provider "oci" {}
variables {
  tenancy_ocid     = "root"
  compartment_ocid = "stack-compartment"
  cluster_id      = "cluster"
  region          = "us-phoenix-1"
}
override_module {
  target = module.target
  outputs = { target = {
    ready = true, issues = [], gpu_image = { id = "gpu-image" }, cpu_image = null, kubernetes_version = "v1.34.1",
    cluster_compartment_id = "cluster-compartment", vcn_id = "vcn", subnet_id = "worker", devops_subnet_id = "runner", pod_subnet_id = null,
    gpu_nsg_ids = [], pod_nsg_ids = [], devops_nsg_ids = [], oke_addons = []
  } }
}
run "rendered_defaults_produce_a_gpu_only_preview" {
  command = plan
  assert {
    condition     = var.node_count == 1 && var.boot_volume_gib == 300 && var.gpu_shape == "BM.GPU.A10.4" && length(module.allocation) == 0 && length(module.bootstrap) == 0 && local.selected_specification.selection_id == "selected"
    error_message = "The rendered ZIP must be prefilled and preview-only without a large JSON variable."
  }
}
run "expert_values_override_recommendations_and_are_disclosed" {
  command = plan
  variables { node_count = 2 }
  assert {
    condition     = var.node_count == 2 && contains(output.infrastructure_preview.selected_recommendation.changed_fields, "node_count") && strcontains(output.infrastructure_preview.selected_recommendation.status, "expert_modified")
    error_message = "Expert edits must reach the plan and invalidate the original sizing claim."
  }
}
run "wrong_region_is_rejected" {
  command = plan
  variables { region = "us-ashburn-1" }
  expect_failures = [terraform_data.specification]
}
