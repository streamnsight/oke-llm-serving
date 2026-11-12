# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {}
mock_provider "http" {}
variables {
  tenancy_ocid           = "root"
  compartment_id         = "target"
  region                 = "region-one"
  cluster_id             = "cluster"
  availability_domain    = "AD-1"
  subnet_id              = "gpu-subnet"
  cpu_subnet_id          = "cpu-subnet"
  devops_subnet_id       = "devops-subnet"
  gpu_image_id           = "gpu-image"
  cpu_image_id           = "cpu-image"
  gpu_shape              = "VM.GPU.A10.1"
  name                   = "fixture"
  node_count             = 1
  requires_rdma          = false
  tensor_parallel_size   = 1
  pipeline_parallel_size = 1
  replicas               = 1
  model                  = "org/model"
  model_revision         = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  engine_image           = "vllm/vllm-openai@sha256:6ee133356d49ed24cee03dd0cda3d3980279a11c107ce3e752c89e76540f41c9"
  engine_version         = "0.32.0"
  context_length         = 512
  concurrency            = 1
  kv_dtype               = "bfloat16"
  observation_id         = "fresh-allocation"
  assessment_id          = "fixture"
}
override_module {
  target = module.model_profile
  outputs = { profile = {
    model                = { chat_template_available = true, pipeline_tag = "text-generation", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
    architecture         = { architectures = ["LlamaForCausalLM"], attention = { layers = 4, heads = 8, kv_heads = 2, hidden_size = 64, vocab_size = 100 } }
    weights              = { elements_by_dtype = { BF16 = 100 }, tensor_data_bytes = 1000000 }
    memory               = { status = "estimated", weight_bytes = 1000000, kv_bytes = 10000, runtime_allowance_bytes = 1000, assumptions = { safety_margin_fraction = 0.2 } }
    serving_requirements = { version_hints = [] }
  } }
}
override_module {
  target  = module.allocation
  outputs = { allocation = { kubernetes_version = "v1.34.1" } }
}
override_module {
  target  = module.delivery
  outputs = { delivery = { bootstrap_rbac = {} } }
}
run "valid_selected_specification" { command = plan }
run "reject_gpu_oversubscription" {
  command = plan
  variables { tensor_parallel_size = 2 }
  expect_failures = [terraform_data.specification]
}
run "reject_changed_model_identity" {
  command = plan
  variables { model_revision = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
  expect_failures = [terraform_data.specification]
}
run "reject_unreviewed_engine_version" {
  command = plan
  variables { engine_version = "99.0.0" }
  expect_failures = [terraform_data.specification]
}

run "frozen_engine_accepts_an_expert_configuration_without_catalog_edit" {
  command = plan
  variables {
    engine_version         = "0.33.0"
    engine_image           = "vllm/vllm-openai@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    expert_configuration   = true
    expert_rank_memory_gib = 10
    serving_configuration  = { status = "requires_expert_configuration", model = { repository = "org/model", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, engine = { version = "0.33.0", image = "vllm/vllm-openai@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", architectures = ["FlintForCausalLM"], framework = "vllm", id = "resolved", gpu_compute_capabilities = [86], platform = "linux/amd64", multi_node_backend = "mp" }, recipe = { args = ["--reasoning-parser", "glm47"], env = { TEST_SETTING = "value" } } }
  }
  override_module {
    target  = module.model_profile
    outputs = { profile = { model = { pipeline_tag = "text-generation", chat_template_available = true, resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, architecture = { architectures = ["FlintForCausalLM"], attention = { layers = 49, heads = 32, kv_heads = 4, head_dim = 128, hidden_size = 2048, vocab_size = 150144 } }, memory = { status = "unsupported", weight_bytes = null, kv_bytes = null, runtime_allowance_bytes = 0, assumptions = { safety_margin_fraction = 0.2 } }, weights = { tensor_data_bytes = 1000000, elements_by_dtype = { BF16 = 500000 } }, serving_requirements = { version_hints = [] } } }
  }
  assert {
    condition     = local.engine_args[0] == "--reasoning-parser" && local.engine_env.TEST_SETTING == "value" && local.engine.version == "0.33.0"
    error_message = "Frozen dynamic engine and recipe args/env must pass through without a static engine catalog edit."
  }
}
run "expert_mode_cannot_bypass_rank_memory_fit" {
  command = plan
  variables {
    expert_configuration   = true
    expert_rank_memory_gib = 1000
  }
  expect_failures = [terraform_data.specification]
}
run "reject_conflicting_recipe_topology_flags" {
  command = plan
  variables { engine_args = ["--tensor-parallel-size", "8"] }
  expect_failures = [terraform_data.specification]
}

run "one_discovery_json_drives_deployment_choices_and_feature_overrides" {
  command = plan
  variables {
    model                  = null
    model_revision         = null
    engine_image           = null
    engine_version         = null
    region                 = null
    availability_domain    = null
    gpu_shape              = null
    context_length         = null
    concurrency            = null
    kv_dtype               = null
    observation_id         = null
    assessment_id          = null
    selection_id           = "choice"
    expert_configuration   = true
    expert_rank_memory_gib = 10
    recipe_features        = ["reasoning"]
    discovery = { discovery = {
      observation_id = "assessment-1"
      profile        = { model = { repository = "org/model", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, memory = { assumptions = { context_length = 2048, concurrency = 3, kv_dtype = "bfloat16", runtime_allowance_gib = 2, safety_margin_fraction = 0.2 } } }
      serving_configuration = {
        status = "resolved_requires_validation", model = { repository = "org/model", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
        engine = { id = "assessed", framework = "vllm", version = "0.33.0", image = "vllm/vllm-openai@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", platform = "linux/amd64", architectures = ["LlamaForCausalLM"], gpu_compute_capabilities = [86], multi_node_backend = "mp", available_images = { "linux/amd64" = "vllm/vllm-openai@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" } }
        recipe = { args = [], env = {}, feature_options = { reasoning = { args = ["--reasoning-parser", "glm47"], env = { FEATURE = "enabled" } } } }
      }
      assessment = { candidates = [], sizing_options = [{ id = "choice", region = "region-one", availability_domain = "AD-1", gpu_shape = "VM.GPU.A10.1", configuration_status = "undetermined_requires_expert" }] }
    } }
  }
  assert {
    condition     = local.model == "org/model" && local.model_revision == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" && local.engine_version == "0.33.0" && local.context_length == 2048 && local.concurrency == 3 && local.region == "region-one"
    error_message = "Model/workload/engine/target evidence must be derived from the single discovery JSON, without an export script or repeated inputs."
  }
  assert {
    condition     = local.engine_args[0] == "--reasoning-parser" && local.engine_env.FEATURE == "enabled" && local.serving_configuration.recipe.selected_features == tolist(["reasoning"])
    error_message = "Features belong to deployment and must be applied from frozen assessment definitions."
  }
}

run "nightly_is_a_deployment_choice_from_the_assessment" {
  command = plan
  variables {
    model                  = null
    model_revision         = null
    engine_image           = null
    engine_version         = null
    region                 = null
    availability_domain    = null
    gpu_shape              = null
    context_length         = null
    concurrency            = null
    kv_dtype               = null
    observation_id         = null
    assessment_id          = null
    node_count             = null
    tensor_parallel_size   = null
    pipeline_parallel_size = null
    replicas               = null
    discovery              = jsondecode(file("tests/fixtures/handoff.json"))

    engine_channel = "nightly"
  }
  assert {
    condition     = local.engine_version == "nightly" && local.engine_image == "vllm/vllm-openai@sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" && local.node_count == 1 && local.tp == 1 && local.pp == 1
    error_message = "Choose a frozen assessed nightly image at deployment without a discovery override or repeated model/topology fields."
  }
}
run "missing_assessed_channel_is_rejected" {
  command = plan
  variables {
    model                  = null
    model_revision         = null
    engine_image           = null
    region                 = null
    availability_domain    = null
    gpu_shape              = null
    context_length         = null
    concurrency            = null
    kv_dtype               = null
    observation_id         = null
    assessment_id          = null
    node_count             = null
    tensor_parallel_size   = null
    pipeline_parallel_size = null
    replicas               = null
    discovery              = jsondecode(file("tests/fixtures/handoff.json"))

    engine_version = "99.0.0"
  }
  expect_failures = [terraform_data.specification]
}
run "image_platform_must_match_the_target_cpu" {
  command = plan
  variables {
    model                  = null
    model_revision         = null
    engine_image           = null
    engine_version         = null
    region                 = null
    availability_domain    = null
    gpu_shape              = null
    context_length         = null
    concurrency            = null
    kv_dtype               = null
    observation_id         = null
    assessment_id          = null
    node_count             = null
    tensor_parallel_size   = null
    pipeline_parallel_size = null
    replicas               = null
    discovery              = jsondecode(file("tests/fixtures/handoff.json"))

    engine_platform = "linux/arm64"
  }
  expect_failures = [terraform_data.specification]
}

run "RMS_accepts_the_same_handoff_as_one_JSON_text_field" {
  command=plan
  variables {
    discovery_json=file("tests/fixtures/handoff.json")
    model=null
    model_revision=null
    engine_image=null
    engine_version=null
    region=null
    availability_domain=null
    gpu_shape=null
    context_length=null
    concurrency=null
    kv_dtype=null
    observation_id=null
    assessment_id=null
    node_count=null
    tensor_parallel_size=null
    pipeline_parallel_size=null
    replicas=null
  }
  assert {
    condition=local.model=="org/model" && local.engine_version=="0.33.0" && local.node_count==1 && local.region=="region-one"
    error_message="RMS must accept exactly the same single JSON document through literal text transport."
  }
}
