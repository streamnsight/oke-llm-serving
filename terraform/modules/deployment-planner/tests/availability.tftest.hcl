# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variables {
  max_nodes_per_replica = 2
  profile = {
    model                = { repository = "org/model", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
    architecture         = { architectures = ["LlamaForCausalLM"], attention = { layers = 4, heads = 8, kv_heads = 2, hidden_size = 64, vocab_size = 100 } }
    weights              = { elements_by_dtype = { BF16 = 100 } }
    memory               = { status = "estimated", weight_bytes = 1000000, kv_bytes = 10000, runtime_allowance_bytes = 1000, assumptions = { safety_margin_fraction = 0.2 } }
    serving_requirements = { version_hints = [] }
  }
  regions = [{
    inventory = {
      region               = "region-one"
      availability_domains = [{ name = "AD-1", shapes = [{ shape = "VM.GPU.A10.1", gpus = 1, rdma_ports = 0, quota_names = ["gpu-a10-count"] }] }]
      limits               = [{ name = "gpu-a10-count", scope_type = "AD", availability_domain = "AD-1", tenancy_limit = 10, resource_availability = { available = 10, status = "observed" } }]
    }
    capacity = { region = "region-one", availability_domains = [{ name = "AD-1", assessment = { observed_at = "2026-11-11T00:00:00Z", shapes = [{ shape = "VM.GPU.A10.1", available_instances = 2, availability_status = "AVAILABLE" }] } }] }
  }]
}

run "capacity_and_limits" {
  command = plan
  assert {
    condition     = length(output.assessment.capacity_and_headroom_shapes) == 1 && output.assessment.shape_observations[0].status == "capacity_and_headroom" && length(output.assessment.limit_increase_recommendations) == 0
    error_message = "Positive capacity, matched limits and observed headroom must be reported together."
  }
}

run "zero_limit_with_capacity" {
  command = plan
  variables {
    regions = [{
      inventory = {
        region               = "region-one"
        availability_domains = [{ name = "AD-1", shapes = [{ shape = "VM.GPU.A10.1", gpus = 1, rdma_ports = 0, quota_names = ["gpu-a10-count"] }] }]
        limits               = [{ name = "gpu-a10-count", scope_type = "AD", availability_domain = "AD-1", tenancy_limit = 0, resource_availability = { available = 0, status = "observed" } }]
      }
      capacity = { region = "region-one", availability_domains = [{ name = "AD-1", assessment = { observed_at = "2026-11-11T00:00:00Z", shapes = [{ shape = "VM.GPU.A10.1", available_instances = 2, availability_status = "AVAILABLE" }] } }] }
    }]
  }
  assert {
    condition     = length(output.assessment.candidates) == 0 && length(output.assessment.capacity_and_headroom_shapes) == 0 && output.assessment.shape_observations[0].status == "limit_increase_required" && output.assessment.limit_increase_recommendations[0].limit_name == "gpu-a10-count" && output.assessment.limit_increase_recommendations[0].region == "region-one"
    error_message = "Observed capacity with a zero configured limit must identify the exact increase to request."
  }
}

run "consumed_headroom" {
  command = plan
  variables {
    regions = [{
      inventory = {
        region               = "region-one"
        availability_domains = [{ name = "AD-1", shapes = [{ shape = "VM.GPU.A10.1", gpus = 1, rdma_ports = 0, quota_names = ["gpu-a10-count"] }] }]
        limits               = [{ name = "gpu-a10-count", scope_type = "AD", availability_domain = "AD-1", tenancy_limit = 10, resource_availability = { available = 0, status = "observed" } }]
      }
      capacity = { region = "region-one", availability_domains = [{ name = "AD-1", assessment = { observed_at = "2026-11-11T00:00:00Z", shapes = [{ shape = "VM.GPU.A10.1", available_instances = 2, availability_status = "AVAILABLE" }] } }] }
    }]
  }
  assert {
    condition     = output.assessment.shape_observations[0].status == "headroom_exhausted" && length(output.assessment.limit_increase_recommendations) == 0
    error_message = "Consumed headroom must not be described as a zero configured limit."
  }
}

run "no_physical_capacity" {
  command = plan
  variables {
    regions = [{
      inventory = {
        region               = "region-one"
        availability_domains = [{ name = "AD-1", shapes = [{ shape = "VM.GPU.A10.1", gpus = 1, rdma_ports = 0, quota_names = ["gpu-a10-count"] }] }]
        limits               = [{ name = "gpu-a10-count", scope_type = "AD", availability_domain = "AD-1", tenancy_limit = 0, resource_availability = { available = 10, status = "observed" } }]
      }
      capacity = { region = "region-one", availability_domains = [{ name = "AD-1", assessment = { observed_at = "2026-11-11T00:00:00Z", shapes = [{ shape = "VM.GPU.A10.1", available_instances = 0, availability_status = "OUT_OF_HOST_CAPACITY" }] } }] }
    }]
  }
  assert {
    condition     = output.assessment.shape_observations[0].status == "no_capacity" && length(output.assessment.limit_increase_recommendations) == 0
    error_message = "A limit recommendation needs positive physical capacity."
  }
}

run "wrong_ad_limit" {
  command = plan
  variables {
    regions = [{
      inventory = {
        region               = "region-one"
        availability_domains = [{ name = "AD-1", shapes = [{ shape = "VM.GPU.A10.1", gpus = 1, rdma_ports = 0, quota_names = ["gpu-a10-count"] }] }]
        limits               = [{ name = "gpu-a10-count", scope_type = "AD", availability_domain = "AD-2", tenancy_limit = 10, resource_availability = { available = 10, status = "observed" } }]
      }
      capacity = { region = "region-one", availability_domains = [{ name = "AD-1", assessment = { observed_at = "2026-11-11T00:00:00Z", shapes = [{ shape = "VM.GPU.A10.1", available_instances = 2, availability_status = "AVAILABLE" }] } }] }
    }]
  }
  assert {
    condition     = output.assessment.shape_observations[0].limit_status == "unknown" && length(output.assessment.capacity_and_headroom_shapes) == 0
    error_message = "Limits from a different AD must not establish entitlement."
  }
}

run "partial_mapping" {
  command = plan
  variables {
    regions = [{
      inventory = {
        region               = "region-one"
        availability_domains = [{ name = "AD-1", shapes = [{ shape = "VM.GPU.A10.1", gpus = 1, rdma_ports = 0, quota_names = ["gpu-a10-count", "missing-limit"] }] }]
        limits               = [{ name = "gpu-a10-count", scope_type = "AD", availability_domain = "AD-1", tenancy_limit = 10, resource_availability = { available = 10, status = "observed" } }]
      }
      capacity = { region = "region-one", availability_domains = [{ name = "AD-1", assessment = { observed_at = "2026-11-11T00:00:00Z", shapes = [{ shape = "VM.GPU.A10.1", available_instances = 2, availability_status = "AVAILABLE" }] } }] }
    }]
  }
  assert {
    condition     = !output.assessment.shape_observations[0].quota_mapping_complete && length(output.assessment.capacity_and_headroom_shapes) == 0
    error_message = "Every shape quota name needs an applicable limit before reporting positive entitlement."
  }
}

run "skipped_headroom" {
  command = plan
  variables {
    regions = [{
      inventory = {
        region               = "region-one"
        availability_domains = [{ name = "AD-1", shapes = [{ shape = "VM.GPU.A10.1", gpus = 1, rdma_ports = 0, quota_names = ["gpu-a10-count"] }] }]
        limits               = [{ name = "gpu-a10-count", scope_type = "AD", availability_domain = "AD-1", tenancy_limit = 10, resource_availability = { available = null, status = "unknown" } }]
      }
      capacity = { region = "region-one", availability_domains = [{ name = "AD-1", assessment = { observed_at = "2026-11-11T00:00:00Z", shapes = [{ shape = "VM.GPU.A10.1", available_instances = 2, availability_status = "AVAILABLE" }] } }] }
    }]
  }
  assert {
    condition     = output.assessment.shape_observations[0].status == "unknown" && length(output.assessment.limit_increase_recommendations) == 0
    error_message = "Skipped headroom must stay unknown."
  }
}

run "zero_limit_skipped_headroom" {
  command = plan
  variables {
    regions = [{
      inventory = {
        region               = "region-one"
        availability_domains = [{ name = "AD-1", shapes = [{ shape = "VM.GPU.A10.1", gpus = 1, rdma_ports = 0, quota_names = ["gpu-a10-count"] }] }]
        limits               = [{ name = "gpu-a10-count", scope_type = "AD", availability_domain = "AD-1", tenancy_limit = "0", resource_availability = { available = null, status = "unknown" } }]
      }
      capacity = { region = "region-one", availability_domains = [{ name = "AD-1", assessment = { observed_at = "2026-11-11T00:00:00Z", shapes = [{ shape = "VM.GPU.A10.1", available_instances = 2, availability_status = "AVAILABLE" }] } }] }
    }]
  }
  assert {
    condition     = length(output.assessment.candidates) == 0 && length(output.assessment.limit_increase_recommendations) == 1
    error_message = "Known zero limits must block candidates even when headroom queries were skipped."
  }
}
