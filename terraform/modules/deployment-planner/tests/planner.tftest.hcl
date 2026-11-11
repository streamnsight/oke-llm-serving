# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variables {
  max_nodes_per_replica = 2
  profile = {
    model                = { repository = "org/model", chat_template_available = true, pipeline_tag = "text-generation", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
    architecture         = { architectures = ["LlamaForCausalLM"], attention = { layers = 4, heads = 8, kv_heads = 2, hidden_size = 64, vocab_size = 100 } }
    weights              = { elements_by_dtype = { BF16 = 100 } }
    memory               = { status = "estimated", weight_bytes = 1000000, kv_bytes = 10000, runtime_allowance_bytes = 1000, assumptions = { safety_margin_fraction = 0.2 } }
    serving_requirements = { version_hints = [] }
  }
  regions = [{
    inventory = {
      region               = "region-one"
      availability_domains = [{ name = "AD-1", shapes = [{ shape = "VM.GPU.A10.1", gpus = 1, rdma_ports = 0, quota_names = ["gpu-a10-count"] }] }]
      limits               = [{ name = "gpu-a10-count", scope_type = "AD", availability_domain = "AD-1", resource_availability = { available = 10, status = "observed" } }]
    }
    capacity = { region = "region-one", availability_domains = [{ name = "AD-1", assessment = { observed_at = "2026-11-11T00:00:00Z", shapes = [{ shape = "VM.GPU.A10.1", available_instances = 2, availability_status = "AVAILABLE" }] } }] }
  }]
}
run "single_gpu_candidate" {
  command = plan
  assert {
    condition     = length(output.assessment.candidates) == 2 && output.assessment.candidates[0].node_count == 1 && output.assessment.candidates[0].runtime_validation == "not_run" && output.assessment.candidates[0].entitlement == "positive_unconverted"
    error_message = "A catalogued single GPU should produce a candidate without claiming runtime or quantity-specific quota validation."
  }
}
run "unsupported_memory" {
  command = plan
  variables {
    profile = { memory = { status = "unsupported" }, architecture = { architectures = ["LlamaForCausalLM"] } }
  }
  assert {
    condition     = length(output.assessment.candidates) == 0 && output.assessment.status == "requires_validation"
    error_message = "Unknown memory/dimensions must not create a feasible GPU candidate."
  }
}
run "insufficient_host_capacity" {
  command = plan
  variables { replicas = 3 }
  assert {
    condition     = length(output.assessment.candidates) == 0
    error_message = "Available instances must cover all replicas without adding alternative shape counts."
  }
}
run "unmet_engine_version" {
  command = plan
  variables {
    engines = [{ id = "too-old", framework = "vllm", version = "0.1.0", image = "unused", architectures = ["LlamaForCausalLM"], gpu_compute_capabilities = [86] }]
    profile = {
      architecture         = { architectures = ["LlamaForCausalLM"] }
      serving_requirements = { version_hints = [{ engine = "vllm", version = "0.8.5", operator = ">=" }] }
      memory               = { status = "unsupported" }
    }
  }
  assert {
    condition     = output.assessment.engine_checks[0].version_hints_satisfied == false && length(output.assessment.candidates) == 0
    error_message = "Engine selection must honor extracted stable version expressions."
  }
}

run "unsupported_architecture_explains_zero_layouts" {
  command = plan
  variables {
    profile = {
      model = {pipeline_tag="text-generation",chat_template_available=true}
      architecture = {architectures=["FlintForCausalLM"]}
      memory = {status="unsupported",reasons=["Architecture requires a dedicated estimator."]}
    }
  }
  assert {
    condition = output.assessment.evaluated_layout_count == 0 && length(output.assessment.candidates) == 0 && length(output.assessment.blocking_reasons) == 2 && strcontains(output.assessment.blocking_reasons[1], "FlintForCausalLM")
    error_message = "Positive hardware observations must not hide unsupported model/engine blockers."
  }
}
