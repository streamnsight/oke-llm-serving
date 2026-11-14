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
}
variables {
  cluster_id = "cluster"
  expected   = { gpu_shape = "BM.GPU.A10.4", availability_domain = "AD-1", node_count = 1, gpu_count_per_host = 4 }
}
run "cluster_only_allows_future_gpu_allocation" {
  command = plan
  assert {
    condition     = output.target.metadata_ready && output.target.platform_name == "llm-platform" && output.target.allocation.gpu_pool_id == null && output.target.binding_mode == "runtime" && output.target.runner_subnet_id == "worker-subnet"
    error_message = "Cluster metadata must suffice to prepare model resources before GPU pools or controllers exist."
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
    condition     = output.target.metadata_ready && output.target.platform_name == "existing-platform" && output.target.gpu_pool_compartment_id == "gpu-compartment" && output.target.node_count == 2 && output.target.expected_availability_domain == "AD-1" && join(",", output.target.pool_availability_domains) == "AD-2"
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
  variables { runner_nsg_ids = ["", " ", null] }
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
