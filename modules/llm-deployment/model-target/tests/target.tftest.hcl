# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
  mock_data "oci_containerengine_cluster" {
    defaults = { compartment_id = "cluster-compartment", state = "ACTIVE", type = "ENHANCED_CLUSTER", kubernetes_version = "v1.34.1", vcn_id = "vcn", endpoint_config = [{ subnet_id = "endpoint-subnet" }] }
  }
  mock_data "oci_containerengine_node_pools" {
    defaults = { node_pools = [{ id = "cpu-pool", state = "ACTIVE", cluster_id = "cluster", node_shape = "VM.Standard.E4.Flex", initial_node_labels = [], freeform_tags = {}, node_config_details = [{ size = 2, nsg_ids = [], placement_configs = [{ subnet_id = "worker-subnet", availability_domain = "AD-1" }] }] }] }
  }
  mock_data "oci_containerengine_node_pool" {
    defaults = {
      cluster_id          = "cluster", compartment_id = "gpu-compartment", node_shape = "BM.GPU.A10.4", state = "CREATING",
      initial_node_labels = [{ key = "oke-llm/allocation", value = "existing-platform" }], freeform_tags = { "oke-llm-allocation" = "retained-identity" },
      node_config_details = [{ size = 2, compute_cluster_id = "", placement_configs = [{ subnet_id = "gpu-subnet", availability_domain = "AD-2" }] }]
    }
  }
  mock_data "oci_core_subnet" { defaults = { vcn_id = "vcn", ipv6cidr_block = "", ipv6cidr_blocks = [] } }
  mock_data "oci_core_network_security_group" { defaults = { vcn_id = "vcn" } }
  mock_data "oci_devops_deploy_pipelines" {
    defaults = { deploy_pipeline_collection = [{ items = [{
      id                         = "onboarding", project_id = "platform-project", compartment_id = "gpu-compartment", display_name = "existing-platform-model-onboarding", state = "ACTIVE",
      deploy_pipeline_parameters = [{ items = [for name in ["MODEL_NAMESPACE", "MODEL_PIPELINE_IDS", "MODEL_PROJECT_ID", "MODEL_GPU_POOL_ID", "MODEL_ACCESS_OPERATION"] : { name = name, default_value = "" }] }]
    }] }] }
  }
  mock_data "oci_devops_project" { defaults = { name = "existing-platform", state = "ACTIVE" } }
  mock_data "oci_devops_deploy_stages" {
    defaults = { deploy_stage_collection = [{ items = [{
      id = "onboarding-stage", deploy_pipeline_id = "onboarding", project_id = "platform-project", state = "ACTIVE", deploy_stage_type = "SHELL", display_name = "authorize-exact-model-pipelines", command_spec_deploy_artifact_id = "onboarding-artifact"
    }] }] }
  }
  mock_data "oci_devops_deploy_artifact" {
    defaults = {
      project_id             = "platform-project", state = "ACTIVE", deploy_artifact_type = "COMMAND_SPEC", argument_substitution_mode = "NONE",
      deploy_artifact_source = [{ deploy_artifact_source_type = "INLINE", base64encoded_content = "env:\n  variables:\n    CLUSTER_ID: cluster\n    PLATFORM_NAME: existing-platform\n    PROJECT_ID: platform-project\n" }]
    }
  }

}
variables {
  cluster_id = "cluster"
  expected   = { gpu_shape = "BM.GPU.A10.4", availability_domain = "AD-1", node_count = 1, gpu_count_per_host = 4 }
}
run "missing_retained_pool_stops_automatic_deployment" {
  command = plan
  assert {
    condition     = !output.target.metadata_ready && anytrue([for issue in output.target.issues : strcontains(issue, "No retained GPU pool")]) && output.target.model_onboarding_pipeline_id == null && length(data.oci_devops_deploy_pipelines.model_onboarding) == 0 && output.target.platform_name == "llm-platform" && output.target.allocation.gpu_pool_id == null && output.target.binding_mode == "runtime" && output.target.runner_subnet_id == "worker-subnet"
    error_message = "Automatic model deployment requires an existing owned GPU allocation and trusted infrastructure onboarding."
  }
  assert {
    condition     = output.target.gpu_readiness != "ready" && output.target.free_gpu_headroom == "unknown_other_namespace_requests_not_visible" && length(data.oci_containerengine_node_pool.selected) == 0
    error_message = "Metadata discovery may not claim live GPUs or free capacity."
  }
}
run "selected_retained_pool_supplies_platform_and_actual_ad" {
  command = plan
  variables { gpu_pool_id = "retained-pool" }
  assert {
    condition     = output.target.metadata_ready && output.target.platform_name == "existing-platform" && output.target.gpu_pool_compartment_id == "gpu-compartment" && output.target.node_count == 2 && output.target.expected_availability_domain == "AD-1" && join(",", output.target.pool_availability_domains) == "AD-2" && output.target.model_onboarding_pipeline_id == "onboarding" && output.target.model_onboarding_project_id == "platform-project" && length(output.target.model_onboarding_revision) == 64
    error_message = "A retained compatible pool may be in another AD and supplies actual ownership/network metadata without waiting for Ready GPU nodes."
  }
}
run "mismatched_shape_is_not_silently_adapted" {
  command = plan
  variables {
    gpu_pool_id = "retained-pool"
    expected    = { gpu_shape = "BM.GPU.H100.8", availability_domain = "AD-1", node_count = 1, gpu_count_per_host = 8 }
  }
  assert {
    condition     = !output.target.metadata_ready && anytrue([for issue in output.target.issues : strcontains(issue, "shape differs")])
    error_message = "Changing hardware requires an appropriate model assessment; metadata lookup must not silently reinterpret the frozen recommendation."
  }
}
run "empty_rms_nsg_rows_do_not_disable_inference" {
  command = plan
  variables {
    gpu_pool_id    = "retained-pool"
    runner_nsg_ids = ["", " ", null]
  }
  assert {
    condition     = output.target.metadata_ready && length(output.target.runner_nsg_ids) == 0
    error_message = "Blank RMS rows are not network security group IDs."
  }
}
run "cluster_only_infers_unique_managed_pool_in_another_ad" {
  command = plan
  override_data {
    target = data.oci_containerengine_node_pools.cluster
    values = {
      "node_pools" : [
        {
          "id" : "pool-other-ad",
          "cluster_id" : "cluster",
          "state" : "ACTIVE",
          "node_shape" : "BM.GPU.A10.4",
          "initial_node_labels" : [
            {
              "key" : "oke-llm/allocation",
              "value" : "existing-platform"
            }
          ],
          "freeform_tags" : {
            "oke-llm-allocation" : "owned-pool-other-ad"
          },
          "node_config_details" : [
            {
              "size" : 2,
              "nsg_ids" : [],
              "placement_configs" : [
                {
                  "subnet_id" : "worker-subnet",
                  "availability_domain" : "AD-2"
                }
              ]
            }
          ]
        }
      ]
    }
  }
  assert {
    condition     = output.target.metadata_ready && output.target.allocation.gpu_pool_id == "pool-other-ad" && output.target.pool_binding == "inferred_unique_managed_pool" && output.target.platform_name == "existing-platform"
    error_message = "A unique compatible retained pool can be reused by cluster ID even when its AD differs from new-allocation discovery."
  }
}
run "auto_lookup_prefers_a_unique_discovery_ad_match" {
  command = plan
  override_data {
    target = data.oci_containerengine_node_pools.cluster
    values = {
      "node_pools" : [
        {
          "id" : "pool-preferred",
          "cluster_id" : "cluster",
          "state" : "ACTIVE",
          "node_shape" : "BM.GPU.A10.4",
          "initial_node_labels" : [
            {
              "key" : "oke-llm/allocation",
              "value" : "existing-platform"
            }
          ],
          "freeform_tags" : {
            "oke-llm-allocation" : "owned-pool-preferred"
          },
          "node_config_details" : [
            {
              "size" : 2,
              "nsg_ids" : [],
              "placement_configs" : [
                {
                  "subnet_id" : "worker-subnet",
                  "availability_domain" : "AD-1"
                }
              ]
            }
          ]
        },
        {
          "id" : "pool-other",
          "cluster_id" : "cluster",
          "state" : "ACTIVE",
          "node_shape" : "BM.GPU.A10.4",
          "initial_node_labels" : [
            {
              "key" : "oke-llm/allocation",
              "value" : "another-platform"
            }
          ],
          "freeform_tags" : {
            "oke-llm-allocation" : "owned-pool-other"
          },
          "node_config_details" : [
            {
              "size" : 2,
              "nsg_ids" : [],
              "placement_configs" : [
                {
                  "subnet_id" : "worker-subnet",
                  "availability_domain" : "AD-2"
                }
              ]
            }
          ]
        }
      ]
    }
  }
  assert {
    condition     = output.target.metadata_ready && output.target.allocation.gpu_pool_id == "pool-preferred"
    error_message = "A unique preferred-AD pool may be inferred without asking the user to choose an arbitrary platform."
  }
}
run "ambiguous_distinct_pools_require_an_explicit_override" {
  command = plan
  override_data {
    target = data.oci_containerengine_node_pools.cluster
    values = {
      "node_pools" : [
        {
          "id" : "pool-a",
          "cluster_id" : "cluster",
          "state" : "ACTIVE",
          "node_shape" : "BM.GPU.A10.4",
          "initial_node_labels" : [
            {
              "key" : "oke-llm/allocation",
              "value" : "platform-a"
            }
          ],
          "freeform_tags" : {
            "oke-llm-allocation" : "owned-pool-a"
          },
          "node_config_details" : [
            {
              "size" : 2,
              "nsg_ids" : [],
              "placement_configs" : [
                {
                  "subnet_id" : "worker-subnet",
                  "availability_domain" : "AD-2"
                }
              ]
            }
          ]
        },
        {
          "id" : "pool-b",
          "cluster_id" : "cluster",
          "state" : "ACTIVE",
          "node_shape" : "BM.GPU.A10.4",
          "initial_node_labels" : [
            {
              "key" : "oke-llm/allocation",
              "value" : "platform-b"
            }
          ],
          "freeform_tags" : {
            "oke-llm-allocation" : "owned-pool-b"
          },
          "node_config_details" : [
            {
              "size" : 2,
              "nsg_ids" : [],
              "placement_configs" : [
                {
                  "subnet_id" : "worker-subnet",
                  "availability_domain" : "AD-3"
                }
              ]
            }
          ]
        }
      ]
    }
  }
  assert {
    condition     = !output.target.metadata_ready && output.target.allocation.gpu_pool_id == null && anytrue([for issue in output.target.issues : strcontains(issue, "Multiple compatible")])
    error_message = "Ambiguity must not silently choose another model's retained pool."
  }
}
run "missing_onboarding_is_a_clear_infrastructure_prerequisite" {
  command = plan
  variables { gpu_pool_id = "retained-pool" }
  override_data {
    target = data.oci_devops_deploy_pipelines.model_onboarding["gpu-compartment"]
    values = { deploy_pipeline_collection = [{ items = [] }] }
  }
  assert {
    condition     = !output.target.metadata_ready && output.target.model_onboarding_pipeline_id == null && anytrue([for issue in output.target.issues : strcontains(issue, "Apply the infrastructure/components stack first")])
    error_message = "Missing trusted onboarding must fail before creating automatic model deployment resources."
  }
}
run "a_pipeline_for_another_cluster_is_never_selected" {
  command = plan
  variables { gpu_pool_id = "retained-pool" }
  override_data {
    target = data.oci_devops_deploy_artifact.model_onboarding["onboarding-artifact"]
    values = {
      project_id             = "platform-project", state = "ACTIVE", deploy_artifact_type = "COMMAND_SPEC", argument_substitution_mode = "NONE",
      deploy_artifact_source = [{ deploy_artifact_source_type = "INLINE", base64encoded_content = "env:\n  variables:\n    CLUSTER_ID: foreign-cluster\n    PLATFORM_NAME: existing-platform\n    PROJECT_ID: platform-project\n" }]
    }
  }
  assert {
    condition     = !output.target.metadata_ready && output.target.model_onboarding_pipeline_id == null
    error_message = "Matching names alone cannot authorize an onboarding pipeline bound to another cluster."
  }
}
run "wrong_platform_project_is_rejected" {
  command = plan
  variables { gpu_pool_id = "retained-pool" }
  override_data {
    target = data.oci_devops_project.platform["platform-project"]
    values = { name = "another-platform", state = "ACTIVE" }
  }
  assert {
    condition     = !output.target.metadata_ready && output.target.model_onboarding_pipeline_id == null
    error_message = "The onboarding pipeline must belong to the retained allocation's named platform project."
  }
}
run "encoded_or_unparseable_command_content_is_not_trusted" {
  command = plan
  variables { gpu_pool_id = "retained-pool" }
  override_data {
    target = data.oci_devops_deploy_artifact.model_onboarding["onboarding-artifact"]
    values = {
      project_id             = "platform-project", state = "ACTIVE", deploy_artifact_type = "COMMAND_SPEC", argument_substitution_mode = "NONE",
      deploy_artifact_source = [{ deploy_artifact_source_type = "INLINE", base64encoded_content = "ZW52OiB7dmFyaWFibGVzOiB7Q0xVU1RFUl9JRDogY2x1c3Rlcn19" }]
    }
  }
  assert {
    condition     = !output.target.metadata_ready && output.target.model_onboarding_pipeline_id == null
    error_message = "The pinned provider supplies raw inline YAML; encoded blobs must not be silently decoded and trusted."
  }
}
run "model_project_compartment_is_also_checked_without_a_form_override" {
  command = plan
  variables {
    gpu_pool_id    = "retained-pool"
    compartment_id = "model-compartment"
  }
  override_data {
    target = data.oci_devops_deploy_pipelines.model_onboarding["gpu-compartment"]
    values = { deploy_pipeline_collection = [{ items = [] }] }
  }
  override_data {
    target = data.oci_devops_deploy_pipelines.model_onboarding["model-compartment"]
    values = { deploy_pipeline_collection = [{ items = [{
      id                         = "onboarding", project_id = "platform-project", compartment_id = "model-compartment", display_name = "existing-platform-model-onboarding", state = "ACTIVE",
      deploy_pipeline_parameters = [{ items = [for name in ["MODEL_NAMESPACE", "MODEL_PIPELINE_IDS", "MODEL_PROJECT_ID", "MODEL_GPU_POOL_ID", "MODEL_ACCESS_OPERATION"] : { name = name, default_value = "" }] }]
    }] }] }
  }
  assert {
    condition     = output.target.metadata_ready && output.target.model_onboarding_pipeline_id == "onboarding" && length(data.oci_devops_deploy_pipelines.model_onboarding) == 3
    error_message = "The existing model stack compartment is an automatic narrow lookup scope, without another user input."
  }
}
run "duplicate_trusted_onboarding_pipelines_are_not_chosen_arbitrarily" {
  command = plan
  variables { gpu_pool_id = "retained-pool" }
  override_data {
    target = data.oci_devops_deploy_pipelines.model_onboarding["gpu-compartment"]
    values = { deploy_pipeline_collection = [{ items = [for id in ["onboarding", "onboarding-duplicate"] : {
      id                         = id, project_id = "platform-project", compartment_id = "gpu-compartment", display_name = "existing-platform-model-onboarding", state = "ACTIVE",
      deploy_pipeline_parameters = [{ items = [for name in ["MODEL_NAMESPACE", "MODEL_PIPELINE_IDS", "MODEL_PROJECT_ID", "MODEL_GPU_POOL_ID", "MODEL_ACCESS_OPERATION"] : { name = name, default_value = "" }] }]
    }] }] }
  }
  override_data {
    target = data.oci_devops_deploy_stages.model_onboarding["onboarding-duplicate"]
    values = { deploy_stage_collection = [{ items = [{
      id = "duplicate-stage", deploy_pipeline_id = "onboarding-duplicate", project_id = "platform-project", state = "ACTIVE", deploy_stage_type = "SHELL", display_name = "authorize-exact-model-pipelines", command_spec_deploy_artifact_id = "onboarding-artifact"
    }] }] }
  }
  assert {
    condition     = !output.target.metadata_ready && output.target.model_onboarding_pipeline_id == null && anytrue([for issue in output.target.issues : strcontains(issue, "Multiple trusted model-onboarding")])
    error_message = "Multiple equally bound pipelines must fail closed instead of granting against an arbitrary infrastructure project."
  }
}
run "unrelated_inventory_does_not_change_the_onboarding_revision" {
  command = plan
  variables {
    gpu_pool_id    = "retained-pool"
    runner_nsg_ids = ["explicit-network-policy"]
  }
  assert {
    condition     = output.target.metadata_ready && output.target.model_onboarding_revision == run.selected_retained_pool_supplies_platform_and_actual_ad.target.model_onboarding_revision
    error_message = "Unrelated target observations and runner overrides must not change the immutable onboarding code identity."
  }
}
run "a_file_backed_or_missing_inline_source_is_not_a_trusted_binding" {
  command = plan
  variables { gpu_pool_id = "retained-pool" }
  override_data {
    target = data.oci_devops_deploy_artifact.model_onboarding["onboarding-artifact"]
    values = {
      project_id             = "platform-project", state = "ACTIVE", deploy_artifact_type = "COMMAND_SPEC", argument_substitution_mode = "NONE",
      deploy_artifact_source = [{ deploy_artifact_source_type = "GENERIC_ARTIFACT", base64encoded_content = null }]
    }
  }
  assert {
    condition     = !output.target.metadata_ready && output.target.model_onboarding_pipeline_id == null && anytrue([for issue in output.target.issues : strcontains(issue, "No ACTIVE trusted")])
    error_message = "An uninspectable command spec must fail with the infrastructure prerequisite issue instead of guessing a trusted target."
  }
}
