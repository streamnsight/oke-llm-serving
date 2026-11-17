# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "http" {}
variables {
 profile={"model": {"repository": "org/dense", "resolved_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "pipeline_tag": "text-generation", "chat_template_available": true}, "architecture": {"architectures": ["DenseForCausalLM"], "declared_context_length": 262144, "attention": {"layers": 16, "heads": 16, "kv_heads": 4, "head_dim": 64, "hidden_size": 1024, "vocab_size": 4096}}, "weights": {"elements_by_dtype": {"BF16": 50000000000}}, "memory": {"status": "heuristic", "runtime_allowance_bytes": 2147483648, "assumptions": {"context_length": 8192, "concurrency": 4, "kv_dtype": "bfloat16", "safety_margin_fraction": 0.2}, "planning": {"weight_bytes": 100000000000, "cache_scenario_bytes": 4000000000, "payload_budget_bytes": 124800000000}}}
 engines=[]
 recipe_api_enabled=true
 serving_resolution={"engine": {"framework": "vllm", "platform": "linux/amd64", "image": "docker.io/vllm/vllm-openai@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "id": "fixture", "version": "0.34.0", "source_commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "architectures": ["DenseForCausalLM"], "gpu_compute_capabilities": [80, 86], "multi_node_backend": "mp"}, "recipe": {"feature_options": {}, "compatible_strategies": ["single_node_tp"]}}
 regions=[{"inventory": {"region": "region-one", "availability_domains": [{"name": "AD-1", "shapes": [{"shape": "BM.GPU.A10.4", "gpus": 4, "rdma_ports": 0, "quota_names": ["gpu-count"]}]}], "limits": [{"name": "gpu-count", "description": "GPUs for test instances", "scope_type": "AD", "availability_domain": "AD-1", "tenancy_limit": 64, "resource_availability": {"status": "observed", "available": 64}}]}, "capacity": {"region": "region-one", "availability_domains": [{"name": "AD-1", "assessment": {"observed_at": "fixture", "shapes": [{"shape": "BM.GPU.A10.4", "available_instances": 4, "availability_status": "AVAILABLE"}]}}]}}]
}

override_data {
 target = data.http.recipe_metadata[0]
 values = {status_code=200,response_body="{\"model\": {\"model_id\": \"org/dense\", \"context_length\": 262144}, \"variants\": {\"default\": {\"precision\": \"bf16\", \"vram_minimum_gb\": 1}}, \"meta\": {\"tasks\": [\"text\"]}}"}
}

override_data {
 target = data.http.recipe_rendering["hardware=h100&variant=default&strategy=single_node_tp"]
 values = {status_code=200,response_body="{\"selection\": {\"hardware\": \"h100\", \"variant\": \"default\", \"strategy\": \"single_node_tp\", \"adjusted\": [], \"features\": []}, \"argv\": [\"vllm\", \"serve\", \"org/dense\", \"--tensor-parallel-size\", \"1\"], \"docker_image\": \"vllm/vllm-openai:fixture\", \"env\": {}}"}
}

override_data {
 target = data.http.recipe_image["vllm/vllm-openai:fixture"]
 values = {status_code=200,response_body="{\"images\": [{\"os\": \"linux\", \"architecture\": \"amd64\", \"digest\": \"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"}]}"}
}

override_data {
 target = data.http.pp_support[0]
 values = {status_code=200,response_body="| Architecture | Models | Plugin Repository |\n| `DenseForCausalLM` | Dense plugin | ✅ |\n\n| Architecture | Models | Example HF Models | [LoRA](lora.md) | [PP](parallel.md) |\n| `DenseForCausalLM` | Dense | org/dense | ✅ | ✅ |\n"}
}

run "two_hosts_form_one_distributed_replica" {
 command = plan
 assert {
 condition = try(anytrue([for o in output.assessment.suggestions : o.tensor_parallel_size==4 && o.pipeline_parallel_size==2 && o.node_count==2 && o.replicas==1 && o.hosts_per_replica==2 && o.platform_plan.components.lws.required && o.platform_plan.topology.network=="ethernet" && o.serving_configuration.recipe.env.NCCL_IB_DISABLE=="1" && o.configuration_origin=="adapted_multi_host_recipe"]),false)
 error_message = "two hosts form one distributed replica"
 }
}

run "only_smallest_fitting_PP_per_TP_is_retained" {
 command = plan
 assert {
 condition = alltrue([for o in output.assessment.suggestions : o.pipeline_parallel_size==(o.tensor_parallel_size==4 ? 2 : 4)])
 error_message = "only smallest fitting PP per TP is retained"
 }
}

run "one_host_cannot_satisfy_two_host_capacity" {
 command = plan
 variables {
 regions=[{"inventory": {"region": "region-one", "availability_domains": [{"name": "AD-1", "shapes": [{"shape": "BM.GPU.A10.4", "gpus": 4, "rdma_ports": 0, "quota_names": ["gpu-count"]}]}], "limits": [{"name": "gpu-count", "description": "GPUs for test instances", "scope_type": "AD", "availability_domain": "AD-1", "tenancy_limit": 64, "resource_availability": {"status": "observed", "available": 64}}]}, "capacity": {"region": "region-one", "availability_domains": [{"name": "AD-1", "assessment": {"observed_at": "fixture", "shapes": [{"shape": "BM.GPU.A10.4", "available_instances": 1, "availability_status": "AVAILABLE"}]}}]}}]
 }
 assert {
 condition = length(output.assessment.suggestions)==0
 error_message = "one host cannot satisfy two host capacity"
 }
}

run "quota_must_cover_every_host" {
 command = plan
 variables {
 regions=[{"inventory": {"region": "region-one", "availability_domains": [{"name": "AD-1", "shapes": [{"shape": "BM.GPU.A10.4", "gpus": 4, "rdma_ports": 0, "quota_names": ["gpu-count"]}]}], "limits": [{"name": "gpu-count", "description": "GPUs for test instances", "scope_type": "AD", "availability_domain": "AD-1", "tenancy_limit": 64, "resource_availability": {"status": "observed", "available": 7}}]}, "capacity": {"region": "region-one", "availability_domains": [{"name": "AD-1", "assessment": {"observed_at": "fixture", "shapes": [{"shape": "BM.GPU.A10.4", "available_instances": 4, "availability_status": "AVAILABLE"}]}}]}}]
 }
 assert {
 condition = length(output.assessment.suggestions)==0
 error_message = "quota must cover every host"
 }
}

run "replicas_require_complete_distinct_host_groups" {
 command = plan
 variables {
 regions=[{"inventory": {"region": "region-one", "availability_domains": [{"name": "AD-1", "shapes": [{"shape": "BM.GPU.A10.4", "gpus": 4, "rdma_ports": 0, "quota_names": ["gpu-count"]}]}], "limits": [{"name": "gpu-count", "description": "GPUs for test instances", "scope_type": "AD", "availability_domain": "AD-1", "tenancy_limit": 64, "resource_availability": {"status": "observed", "available": 64}}]}, "capacity": {"region": "region-one", "availability_domains": [{"name": "AD-1", "assessment": {"observed_at": "fixture", "shapes": [{"shape": "BM.GPU.A10.4", "available_instances": 3, "availability_status": "AVAILABLE"}]}}]}}]
 replicas=2
 }
 assert {
 condition = length(output.assessment.suggestions)==0
 error_message = "replicas require complete distinct host groups"
 }
}

run "two_replicas_reserve_four_hosts" {
 command = plan
 variables {
 regions=[{"inventory": {"region": "region-one", "availability_domains": [{"name": "AD-1", "shapes": [{"shape": "BM.GPU.A10.4", "gpus": 4, "rdma_ports": 0, "quota_names": ["gpu-count"]}]}], "limits": [{"name": "gpu-count", "description": "GPUs for test instances", "scope_type": "AD", "availability_domain": "AD-1", "tenancy_limit": 64, "resource_availability": {"status": "observed", "available": 64}}]}, "capacity": {"region": "region-one", "availability_domains": [{"name": "AD-1", "assessment": {"observed_at": "fixture", "shapes": [{"shape": "BM.GPU.A10.4", "available_instances": 4, "availability_status": "AVAILABLE"}]}}]}}]
 replicas=2
 }
 assert {
 condition = try(length(output.assessment.suggestions)==1 && output.assessment.suggestions[0].node_count==4 && output.assessment.suggestions[0].replicas==2,false)
 error_message = "two replicas reserve four hosts"
 }
}

run "AD_capacity_must_not_be_combined" {
 command = plan
 variables {
 regions=[{"inventory": {"region": "region-one", "availability_domains": [{"name": "AD-1", "shapes": [{"shape": "BM.GPU.A10.4", "gpus": 4, "rdma_ports": 0, "quota_names": ["gpu-count"]}]}, {"name": "AD-2", "shapes": [{"shape": "BM.GPU.A10.4", "gpus": 4, "rdma_ports": 0, "quota_names": ["gpu-count"]}]}], "limits": [{"name": "gpu-count", "description": "GPUs for test instances", "scope_type": "AD", "availability_domain": "AD-1", "tenancy_limit": 64, "resource_availability": {"status": "observed", "available": 64}}, {"name": "gpu-count", "description": "GPUs for test instances", "scope_type": "AD", "availability_domain": "AD-2", "tenancy_limit": 64, "resource_availability": {"status": "observed", "available": 64}}]}, "capacity": {"region": "region-one", "availability_domains": [{"name": "AD-1", "assessment": {"observed_at": "fixture", "shapes": [{"shape": "BM.GPU.A10.4", "available_instances": 1, "availability_status": "AVAILABLE"}]}}, {"name": "AD-2", "assessment": {"observed_at": "fixture", "shapes": [{"shape": "BM.GPU.A10.4", "available_instances": 1, "availability_status": "AVAILABLE"}]}}]}}]
 }
 assert {
 condition = length(output.assessment.suggestions)==0
 error_message = "AD capacity must not be combined"
 }
}

run "missing_PP_support_is_not_a_LoRA_tick" {
 command = plan

override_data {
 target = data.http.pp_support[0]
 values = {status_code=200,response_body="| Architecture | Models | Plugin Repository |\n| `DenseForCausalLM` | Dense plugin | ✅ |\n\n| Architecture | Models | LoRA | [PP](parallel.md) |\n| `DenseForCausalLM` | Dense | ✅ | ❌ |\n"}
}
 assert {
 condition = length(output.assessment.suggestions)==0
 error_message = "missing PP support is not a LoRA tick"
 }
}

run "unknown_support_table_fails_closed" {
 command = plan

override_data {
 target = data.http.pp_support[0]
 values = {status_code=200,response_body="| Architecture | Models | LoRA | Other feature |\n| `DenseForCausalLM` | Dense | ✅ | ✅ |\n"}
}
 assert {
 condition = length(output.assessment.suggestions)==0
 error_message = "unknown support table fails closed"
 }
}

run "unsupported_backend_is_excluded" {
 command = plan
 variables {
 serving_resolution={"engine": {"framework": "vllm", "platform": "linux/amd64", "image": "docker.io/vllm/vllm-openai@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "id": "fixture", "version": "0.34.0", "source_commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "architectures": ["DenseForCausalLM"], "gpu_compute_capabilities": [80, 86], "multi_node_backend": "ray"}, "recipe": {"feature_options": {}, "compatible_strategies": ["single_node_tp"]}}
 }
 assert {
 condition = length(output.assessment.suggestions)==0
 error_message = "unsupported backend is excluded"
 }
}

run "multi_host_does_not_bypass_FP8_gpu_support" {
 command = plan
 variables {
 profile={"model": {"repository": "org/dense", "resolved_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "pipeline_tag": "text-generation", "chat_template_available": true}, "architecture": {"architectures": ["DenseForCausalLM"], "declared_context_length": 262144, "attention": {"layers": 16, "heads": 16, "kv_heads": 4, "head_dim": 64, "hidden_size": 1024, "vocab_size": 4096}, "quantization": {"quant_method": "fp8"}}, "weights": {"elements_by_dtype": {"F8_E4M3": 100}}, "memory": {"status": "heuristic", "runtime_allowance_bytes": 2147483648, "assumptions": {"context_length": 8192, "concurrency": 4, "kv_dtype": "bfloat16", "safety_margin_fraction": 0.2}, "planning": {"weight_bytes": 100000000000, "cache_scenario_bytes": 4000000000, "payload_budget_bytes": 124800000000}}}
 }
 assert {
 condition = length(output.assessment.suggestions)==0
 error_message = "multi host does not bypass FP8 gpu support"
 }
}

run "requested_context_must_be_supported" {
 command = plan
 variables {
 profile={"model": {"repository": "org/dense", "resolved_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "pipeline_tag": "text-generation", "chat_template_available": true}, "architecture": {"architectures": ["DenseForCausalLM"], "declared_context_length": 4096, "attention": {"layers": 16, "heads": 16, "kv_heads": 4, "head_dim": 64, "hidden_size": 1024, "vocab_size": 4096}}, "weights": {"elements_by_dtype": {"BF16": 50000000000}}, "memory": {"status": "heuristic", "runtime_allowance_bytes": 2147483648, "assumptions": {"context_length": 8192, "concurrency": 4, "kv_dtype": "bfloat16", "safety_margin_fraction": 0.2}, "planning": {"weight_bytes": 100000000000, "cache_scenario_bytes": 4000000000, "payload_budget_bytes": 124800000000}}}
 }
 assert {
 condition = length(output.assessment.suggestions)==0
 error_message = "requested context must be supported"
 }
}

run "missing_partition_dimensions_is_excluded" {
 command = plan
 variables {
 profile={"model": {"repository": "org/dense", "resolved_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "pipeline_tag": "text-generation", "chat_template_available": true}, "architecture": {"architectures": ["DenseForCausalLM"], "declared_context_length": 262144, "attention": {"heads": 16, "kv_heads": 4, "head_dim": 64, "hidden_size": 1024, "vocab_size": 4096}}, "weights": {"elements_by_dtype": {"BF16": 50000000000}}, "memory": {"status": "heuristic", "runtime_allowance_bytes": 2147483648, "assumptions": {"context_length": 8192, "concurrency": 4, "kv_dtype": "bfloat16", "safety_margin_fraction": 0.2}, "planning": {"weight_bytes": 100000000000, "cache_scenario_bytes": 4000000000, "payload_budget_bytes": 124800000000}}}
 }
 assert {
 condition = length(output.assessment.suggestions)==0
 error_message = "missing partition dimensions is excluded"
 }
}

run "host_search_bound_is_respected" {
 command = plan
 variables {
 max_nodes_per_replica=1
 }
 assert {
 condition = length(output.assessment.suggestions)==0
 error_message = "host search bound is respected"
 }
}

run "coupled_speculative_features_are_not_assumed_PP_safe" {
 command = plan

override_data {
 target = data.http.recipe_rendering["hardware=h100&variant=default&strategy=single_node_tp"]
 values = {status_code=200,response_body="{\"selection\": {\"hardware\": \"h100\", \"variant\": \"default\", \"strategy\": \"single_node_tp\", \"adjusted\": [], \"features\": []}, \"argv\": [\"vllm\", \"serve\", \"org/dense\", \"--tensor-parallel-size\", \"1\", \"--speculative-config\", \"{\\\"method\\\":\\\"mtp\\\"}\"], \"docker_image\": \"vllm/vllm-openai:fixture\", \"env\": {}}"}
}
 assert {
 condition = length(output.assessment.suggestions)==0
 error_message = "coupled speculative features are not assumed PP safe"
 }
}

run "unknown_architecture_PP_keeps_memory_sizing" {
 command = plan

override_data {
 target = data.http.pp_support[0]
 values = {status_code=200,response_body="| Architecture | Models | LoRA | [PP](parallel.md) |\n| `DifferentModel` | Dense | ✅ | ✅ |\n"}
}
 assert {
 condition = length(output.assessment.suggestions)==0 && length(output.assessment.sizing_diagnostics)>0
 error_message = "unknown architecture PP keeps memory sizing"
 }
}

run "KV_head_replication_is_reserved_when_TP_exceeds_KV_heads" {
 command = plan
 variables {
 profile={"model": {"repository": "org/dense", "resolved_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "pipeline_tag": "text-generation", "chat_template_available": true}, "architecture": {"architectures": ["DenseForCausalLM"], "declared_context_length": 262144, "attention": {"layers": 16, "heads": 16, "kv_heads": 4, "head_dim": 64, "hidden_size": 1024, "vocab_size": 4096}}, "weights": {"elements_by_dtype": {"BF16": 50000000000}}, "memory": {"status": "heuristic", "runtime_allowance_bytes": 2147483648, "assumptions": {"context_length": 8192, "concurrency": 4, "kv_dtype": "bfloat16", "safety_margin_fraction": 0.2}, "planning": {"weight_bytes": 100000000000, "cache_scenario_bytes": 128000000000, "payload_budget_bytes": 273600000000}}}
 regions=[{"inventory": {"region": "region-one", "availability_domains": [{"name": "AD-1", "shapes": [{"shape": "BM.GPU.B4.8", "gpus": 8, "rdma_ports": 0, "quota_names": ["gpu-count"]}]}], "limits": [{"name": "gpu-count", "description": "GPUs for test instances", "scope_type": "AD", "availability_domain": "AD-1", "tenancy_limit": 64, "resource_availability": {"status": "observed", "available": 64}}]}, "capacity": {"region": "region-one", "availability_domains": [{"name": "AD-1", "assessment": {"observed_at": "fixture", "shapes": [{"shape": "BM.GPU.B4.8", "available_instances": 2, "availability_status": "AVAILABLE"}]}}]}}]
 max_nodes_per_replica=2
 }
 assert {
 condition = try(anytrue([for o in output.assessment.suggestions : o.tensor_parallel_size==8 && o.pipeline_parallel_size==2 && o.estimated_rank_bytes>30000000000 && o.estimated_rank_bytes<=36000000000]),false)
 error_message = "KV head replication is reserved when TP exceeds KV heads"
 }
}

run "fitting_single_host_does_not_gain_extra_PP_hosts" {
 command = plan
 variables {
 profile={"model": {"repository": "org/dense", "resolved_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "pipeline_tag": "text-generation", "chat_template_available": true}, "architecture": {"architectures": ["DenseForCausalLM"], "declared_context_length": 262144, "attention": {"layers": 16, "heads": 16, "kv_heads": 4, "head_dim": 64, "hidden_size": 1024, "vocab_size": 4096}}, "weights": {"elements_by_dtype": {"BF16": 50000000000}}, "memory": {"status": "heuristic", "runtime_allowance_bytes": 2147483648, "assumptions": {"context_length": 8192, "concurrency": 4, "kv_dtype": "bfloat16", "safety_margin_fraction": 0.2}, "planning": {"weight_bytes": 30000000000, "cache_scenario_bytes": 1000000000, "payload_budget_bytes": 37200000000}}}
 }
 assert {
 condition = length(output.assessment.suggestions)==1 && alltrue([for o in output.assessment.suggestions : o.pipeline_parallel_size==1])
 error_message = "fitting single host does not gain extra PP hosts"
 }
}

run "uneven_stages_include_imbalance_and_embeddings" {
 command = plan
 variables {
 profile={"model": {"repository": "org/dense", "resolved_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "pipeline_tag": "text-generation", "chat_template_available": true}, "architecture": {"architectures": ["DenseForCausalLM"], "declared_context_length": 262144, "attention": {"layers": 17, "heads": 16, "kv_heads": 4, "head_dim": 64, "hidden_size": 1024, "vocab_size": 4096}}, "weights": {"elements_by_dtype": {"BF16": 50000000000}}, "memory": {"status": "heuristic", "runtime_allowance_bytes": 2147483648, "assumptions": {"context_length": 8192, "concurrency": 4, "kv_dtype": "bfloat16", "safety_margin_fraction": 0.2}, "planning": {"weight_bytes": 100000000000, "cache_scenario_bytes": 4000000000, "payload_budget_bytes": 124800000000}}}
 }
 assert {
 condition = try(alltrue([for o in output.assessment.suggestions : o.estimated_rank_bytes > 124800000000/(o.tensor_parallel_size*o.pipeline_parallel_size)+2147483648]),false)
 error_message = "uneven stages include imbalance and embeddings"
 }
}

run "LMCache_profile_is_not_silently_sent_to_the_single_host_only_adapter" {
 command=plan
 override_data {
  target=data.http.recipe_rendering["hardware=h100&variant=default&strategy=single_node_tp"]
  values={status_code=200,response_body="{\"selection\":{\"hardware\":\"h100\",\"variant\":\"default\",\"strategy\":\"single_node_tp\",\"adjusted\":[],\"features\":[]},\"argv\":[\"vllm\",\"serve\",\"org/dense\",\"--tensor-parallel-size\",\"1\"],\"docker_image\":\"vllm/vllm-openai:fixture\",\"env\":{},\"deployment_profile\":{\"lmcache\":{\"mode\":\"mp\"}}}"}
 }
 assert {
  condition=length(output.assessment.suggestions)==0
  error_message="The existing LMCache adapter rejects PP; discovery must not produce that unsupported combination."
 }
}
