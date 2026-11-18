# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "external" {}
mock_provider "http" {
  mock_data "http" { defaults = { status_code = 404, response_body = "{}" } }
}
mock_provider "oci" {}
mock_provider "archive" {}
variables {
  tenancy_ocid                   = "fixture-root"
  region                         = "us-chicago-1"
  model                          = "org/model"
  max_hosts_per_replica          = 1
  publish_infrastructure_bundles = false
}
override_module {
  target = module.oci_discovery
  outputs = { result = {
    home_region = "us-chicago-1", subscribed_regions = ["us-chicago-1"], assessed_regions = ["us-chicago-1"],
    regions = [{
      inventory = { region = "us-chicago-1", availability_domains = [{ name = "AD-1", shapes = [{ shape = "VM.GPU.A10.1", gpus = 1, gpu_memory_bytes_per_gpu = 24000000000, rdma_ports = 0, quota_names = ["gpu-a10-count"] }] }],
      limits = [{ name = "gpu-a10-count", description = "GPUs for test instances", tenancy_limit = 2, scope_type = "AD", availability_domain = "AD-1", resource_availability = { available = 2, status = "observed" } }] },
      capacity = { region = "us-chicago-1", availability_domains = [{ name = "AD-1", assessment = { observed_at = "fixture", shapes = [{ shape = "VM.GPU.A10.1", available_instances = 2, availability_status = "AVAILABLE" }] } }] }
    }]
  } }
}
override_module {
  target = module.model_profile
  outputs = { profile = {
    model                = { repository = "org/model", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", chat_template_available = true, pipeline_tag = "text-generation" },
    architecture         = { architectures = ["LlamaForCausalLM"], attention = { layers = 4, heads = 8, kv_heads = 2, hidden_size = 64, vocab_size = 100 } },
    weights              = { elements_by_dtype = { BF16 = 100 } },
    memory               = { status = "estimated", weight_bytes = 1000000, kv_bytes = 10000, runtime_allowance_bytes = 1000, assumptions = { safety_margin_fraction = 0.2, context_length = 4096, concurrency = 1 } },
    serving_requirements = { version_hints = [] }
  } }
}
override_module {
  target  = module.serving_resolution
  outputs = { resolution = { engine_issues = [], engine = { id = "fixture", framework = "vllm", version = "0.33.0", image = "docker.io/vllm/vllm-openai@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", platform = "linux/amd64", architectures = ["LlamaForCausalLM"], gpu_compute_capabilities = [86], multi_node_backend = "mp" } } }
}
run "root_replica_request_controls_real_planner_host_quantities" {
  command = plan
  variables { replicas = 2 }
  assert {
    condition     = length(module.planner.assessment.candidates) > 0 && alltrue([for c in module.planner.assessment.candidates : c.node_count == 2 && c.replicas == 2 && c.requested_minimum_replicas == 2 && c.platform_plan.workload.estimated_aggregate_concurrency == 2])
    error_message = "The discovery root must forward two replicas into real planner capacity, headroom and workload calculations."
  }
}
run "replicas_above_capacity_produce_no_deployment_option" {
  command = plan
  variables { replicas = 3 }
  assert {
    condition     = length(module.planner.assessment.candidates) == 0 && length(module.planner.assessment.suggestions) == 0
    error_message = "Replica requests above confirmed capacity/headroom must not produce deployment options."
  }
}
run "zero_replicas_is_invalid" {
  command = plan
  variables { replicas = 0 }
  expect_failures = [var.replicas]
}
run "fractional_replicas_is_invalid" {
  command = plan
  variables { replicas = 1.5 }
  expect_failures = [var.replicas]
}
