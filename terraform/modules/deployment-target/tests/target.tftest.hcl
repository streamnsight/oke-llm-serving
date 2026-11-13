# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
  mock_data "oci_core_network_security_group" { defaults = { vcn_id = "vcn" } }
  mock_data "oci_containerengine_cluster" {
    defaults = {
      compartment_id = "cluster-compartment", vcn_id = "vcn", state = "ACTIVE", type = "ENHANCED_CLUSTER", kubernetes_version = "v1.34.1", endpoint_config = [{
        subnet_id = "api"
        }
        ], cluster_pod_network_options = [{
          cni_type = "OCI_VCN_IP_NATIVE"
        }
      ]
    }
  }
  mock_data "oci_containerengine_node_pools" {
    defaults = {
      node_pools = [{
        state = "ACTIVE", node_config_details = [{
          nsg_ids = ["worker-nsg"],
          placement_configs = [{
            subnet_id = "worker"
            }
            ], node_pool_pod_network_option_details = [{
              pod_nsg_ids    = ["pod-nsg"],
              pod_subnet_ids = ["pods"]
            }
          ]
          }
        ]
        }
      ]
    }
  }
  mock_data "oci_containerengine_addons" {
    defaults = {
      addons = []
    }
  }
  mock_data "oci_core_subnet" {
    defaults = {
      vcn_id = "vcn", availability_domain = "", prohibit_public_ip_on_vnic = true
    }
  }
}
variables {
  cluster_id          = "cluster"
  availability_domain = "AD-1"
  gpu_shape           = "VM.GPU.A10.1"
  gpu_architecture    = "amd64"
  cpu_shape           = "VM.Standard.E4.Flex"
  os_version          = "8"
  overrides = {
    gpu_image_id = null, cpu_image_id = null, subnet_id = null, cpu_subnet_id = null, devops_subnet_id = null, pod_subnet_id = null
  }
}
override_module {
  target = module.gpu_image
  outputs = {
    image = {
      id = "gpu-image"
    }
  }
}
override_module {
  target = module.cpu_image
  outputs = {
    image = {
      id = "cpu-image"
    }
  }
}
run "derive_existing_cluster_network" {
  command = plan
  assert {
    condition     = output.target.ready && output.target.subnet_id == "worker" && output.target.devops_subnet_id == "worker" && output.target.pod_subnet_id == "pods"
    error_message = "Reuse known worker/pod networking and preserve its path to the cluster API."
  }
}
run "ambiguous_workers_need_an_override" {
  command = plan
  override_data {
    target = data.oci_containerengine_node_pools.target
    values = {
      node_pools = [{
        state = "ACTIVE", node_config_details = [{
          nsg_ids = ["worker-nsg"],
          placement_configs = [{
            subnet_id = "worker"
            }
            , {
              subnet_id = "other"
            }
            ], node_pool_pod_network_option_details = [{
              pod_nsg_ids    = ["pod-nsg"],
              pod_subnet_ids = ["pods"]
            }
          ]
          }
        ]
        }
      ]
    }
  }
  assert {
    condition     = !output.target.ready && output.target.subnet_id == null && length(output.target.subnet_choices.workers) == 2
    error_message = "Never pick an arbitrary subnet when existing worker networks disagree."
  }
}
run "cross_vcn_override_is_rejected" {
  command = plan
  variables {
    overrides = {
      gpu_image_id = null, cpu_image_id = null, subnet_id = "foreign", cpu_subnet_id = null, devops_subnet_id = null, pod_subnet_id = null
    }
  }
  override_data {
    target = data.oci_core_subnet.candidate["foreign"]
    values = {
      vcn_id = "foreign-vcn", availability_domain = "", prohibit_public_ip_on_vnic = true
    }
  }
  expect_failures = [output.target]
}
run "wrong_ad_is_reported_without_allocating" {
  command = plan
  override_data {
    target = data.oci_core_subnet.candidate["worker"]
    values = {
      vcn_id = "vcn", availability_domain = "AD-2", prohibit_public_ip_on_vnic = true
    }
  }
  assert {
    condition     = !output.target.ready && output.target.subnet_id == null
    error_message = "AD-specific subnets from another AD cannot be reused."
  }
}
run "retain_existing_worker_and_pod_nsgs" {
  command = plan
  assert {
    condition     = one(output.target.gpu_nsg_ids) == "worker-nsg" && one(output.target.devops_nsg_ids) == "worker-nsg" && one(output.target.pod_nsg_ids) == "pod-nsg"
    error_message = "New nodes and the pipeline VNIC must retain the existing cluster network security groups, not just reuse the subnet."
  }
}
run "cross_vcn_nsg_is_rejected" {
  command = plan
  variables { worker_nsg_ids = ["foreign-nsg"] }
  override_data {
    target = data.oci_core_network_security_group.selected["foreign-nsg"]
    values = { vcn_id = "other-vcn" }
  }
  expect_failures = [output.target]
}
run "existing_public_worker_network_is_not_arbitrarily_forbidden" {
  command = plan
  override_data {
    target = data.oci_core_subnet.candidate["worker"]
    values = { vcn_id = "vcn", availability_domain = "", prohibit_public_ip_on_vnic = false }
  }
  assert {
    condition     = output.target.ready && !output.target.subnet_checks.gpu.private
    error_message = "Record subnet exposure without inventing a requirement that existing OKE worker subnets be private."
  }
}
run "ambiguous_nsg_policy_needs_an_override" {
  command = plan
  override_data {
    target = data.oci_containerengine_node_pools.target
    values = { node_pools = [{ state = "ACTIVE", node_config_details = [
      { nsg_ids = ["one"], placement_configs = [{ subnet_id = "worker" }], node_pool_pod_network_option_details = [{ pod_subnet_ids = ["pods"], pod_nsg_ids = [] }] },
      { nsg_ids = ["two"], placement_configs = [{ subnet_id = "worker" }], node_pool_pod_network_option_details = [{ pod_subnet_ids = ["pods"], pod_nsg_ids = [] }] }
    ] }] }
  }
  assert {
    condition     = !output.target.ready && anytrue([for issue in output.target.issues : strcontains(issue, "NSG policies")])
    error_message = "Reusing a subnet cannot silently discard conflicting existing NSG policies."
  }
}
run "RDMA_requires_enhanced_cluster_in_preview" {
  command = plan
  variables { requires_rdma = true }
  override_data {
    target = data.oci_containerengine_cluster.target
    values = { compartment_id = "cluster-compartment", vcn_id = "vcn", state = "ACTIVE", type = "BASIC_CLUSTER", kubernetes_version = "v1.34.1", endpoint_config = [{ subnet_id = "api" }], cluster_pod_network_options = [{ cni_type = "OCI_VCN_IP_NATIVE" }] }
  }
  assert {
    condition     = !output.target.ready && anytrue([for issue in output.target.issues : strcontains(issue, "enhanced OKE")])
    error_message = "Show a missing RDMA cluster prerequisite before creating any resources."
  }
}
run "existing_cpu_pools_need_no_cpu_image_discovery" {
  command = plan
  variables { resolve_cpu_image = false }
  assert {
    condition     = length(module.cpu_image) == 0 && output.target.cpu_image == null && output.target.ready
    error_message = "Skip CPU image discovery entirely when reusing the existing cluster CPU pools."
  }
}
