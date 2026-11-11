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
