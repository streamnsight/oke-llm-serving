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
      limits               = [{ name="gpu-a10-count", description="GPUs for test instances", tenancy_limit=10, scope_type = "AD", availability_domain = "AD-1", resource_availability = { available = 10, status = "observed" } }]
    }
    capacity = { region = "region-one", availability_domains = [{ name = "AD-1", assessment = { observed_at = "2026-11-11T00:00:00Z", shapes = [{ shape = "VM.GPU.A10.1", available_instances = 2, availability_status = "AVAILABLE" }] } }] }
  }]
}
run "single_gpu_candidate" {
  command = plan
  assert {
    condition     = length(output.assessment.candidates) == 2 && output.assessment.candidates[0].node_count == 1 && output.assessment.candidates[0].runtime_validation == "not_run" && output.assessment.candidates[0].entitlement == "confirmed_for_quantity"
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

run "flint_sizing_options_do_not_invent_a_serving_layout" {
  command = plan
  variables {
    profile = {
      model={repository="RecursiveSI/flint",resolved_revision="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",pipeline_tag="text-generation",chat_template_available=true}
      architecture={model_type="flint",architectures=["FlintForCausalLM"],quantization=null,attention={layers=49,heads=32,kv_heads=4,head_dim=128,hidden_size=2048,vocab_size=150144,layer_types=concat([for i in range(14):"full_attention"],[for i in range(35):"sliding_attention"])}}
      weights={selected_checkpoint="model.safetensors.index.json",tensor_data_bytes=79570574912,tensor_elements=39785287456,elements_by_dtype={BF16=39785287456}}
      memory={status="unsupported",weight_bytes=null,kv_bytes=null,reasons=["Dedicated layout estimator unsupported"],runtime_allowance_bytes=2147483648,assumptions={kv_dtype="bfloat16",context_length=4096,concurrency=4,safety_margin_fraction=0.2}}
      serving_requirements={version_hints=[]}
    }
    engines=[{id="vllm-0.33.0",framework="vllm",version="0.33.0",image="fixture",architectures=["FlintForCausalLM"],gpu_compute_capabilities=[86],platform="linux/amd64",multi_node_backend="mp"}]
    serving_resolution={status="resolved_requires_validation",recipe={hardware={gb200="verified"},selected_hardware="gb200"},engine={platform="linux/amd64"}}
  }
  assert {
    condition=length(output.assessment.candidates)==0 && output.assessment.status=="requires_validation" && output.assessment.sizing_diagnostics[0].estimated_minimum_gpus==5 && output.assessment.sizing_diagnostics[0].configuration_status=="undetermined_requires_expert" && output.assessment.sizing_diagnostics[0].recipe_hardware_status=="no_tested_recipe_for_this_hardware"
    error_message="Flint on A10 must expose a memory-only lower bound, not fabricate TP/PP or claim runtime feasibility."
  }
  assert {
    condition=output.assessment.recipe_hardware_targets[0].gpu_shape=="BM.GPU.GB200.4" && output.assessment.recipe_hardware_targets[0].image_platform=="linux/arm64"
    error_message="Identify the actual recipe hardware/platform even when it is absent from the scanned inventory."
  }
}
run "image_platform_is_assessed_per_hardware_without_a_discovery_override" {
  command=plan
  variables {
    engines=[{id="resolved",framework="vllm",version="0.33.0",image="vllm/image@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",platform="linux/amd64",available_images={"linux/arm64"="vllm/image@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"},architectures=["LlamaForCausalLM"],gpu_compute_capabilities=[100],multi_node_backend="mp"}]
    serving_resolution={status="resolved_requires_validation",recipe={hardware={gb200="verified"},selected_hardware="gb200",compatible_strategies=["single_node_tp"],strategy_overrides={single_node_tp={tp=1}},variant_metadata={}}}
    regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="BM.GPU.GB200.4",gpus=4,rdma_ports=0,quota_names=["gpu-count"]}]}],limits=[{name="gpu-count",description="GPUs for test instances",scope_type="AD",availability_domain="AD-1",tenancy_limit=64,resource_availability={status="observed",available=64}}]},capacity={region="region-one",availability_domains=[{name="AD-1",assessment={observed_at="test",shapes=[{shape="BM.GPU.GB200.4",available_instances=2,availability_status="AVAILABLE"}]}}]}}]
  }
  assert {
    condition=anytrue([for c in output.assessment.candidates : c.engine.platform=="linux/arm64" && c.configuration_status=="recipe_configuration_requires_validation" && c.engine.image=="vllm/image@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"])
    error_message="A published ARM image must be selected automatically for Grace hardware, without an image-platform choice in discovery."
  }
}
run "uncatalogued_gpu_does_not_crash_resolved_image_selection" {
  command = plan
  variables {
    gpu_catalog = {}
    engines = [{id="resolved",framework="vllm",version="0.33.0",image="fixture",platform="linux/amd64",available_images={"linux/amd64"="fixture"},architectures=["LlamaForCausalLM"],gpu_compute_capabilities=[86]}]
    serving_resolution = {status="resolved_requires_validation",recipe={}}
  }
  assert {
    condition = length(output.assessment.candidates) == 0 && output.assessment.shape_observations[0].catalog_known == false
    error_message = "Unknown GPU metadata must remain an observation, without crashing or inventing a deployable image/layout."
  }
}
