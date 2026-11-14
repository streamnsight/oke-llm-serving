# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Baseline for the components this stack actually deploys, including one CPU
# benchmark job. Does not claim HA or throughput sizing from model weights.
output "requirements" {
  value = {
    node_count = 1, shape = "VM.Standard.E4.Flex", ocpus = 4, memory_gib = 24,
    budget     = { router_vcpu = 1, controllers_vcpu = 2, benchmark_vcpu = 2, system_vcpu = 2, memory_gib = 20 },
    status     = "component_budget_estimate_single_node_no_ha"
  }
}
