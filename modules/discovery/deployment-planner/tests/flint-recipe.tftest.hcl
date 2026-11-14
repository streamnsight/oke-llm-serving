# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "http" {}
variables {
 recipe_api_enabled=true
 profile={model={repository="RecursiveSI/flint",resolved_revision="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",pipeline_tag="text-generation",chat_template_available=true},architecture={architectures=["FlintForCausalLM"],attention={heads=32,kv_heads=4}},memory={status="unsupported",runtime_allowance_bytes=2147483648,assumptions={context_length=4096,concurrency=4,kv_dtype="bfloat16"},reasons=["hybrid estimator missing"]}}
 engines=[]
 serving_resolution={engine={platform="linux/amd64",image="fixture",version="0.33.0",architectures=["FlintForCausalLM"],gpu_compute_capabilities=[90],multi_node_backend="mp"},recipe={}}
 regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="BM.GPU.H100.8",gpus=8,rdma_ports=0,quota_names=["gpu-count"]}]}],limits=[{name="gpu-count",description="GPUs for test instances",scope_type="AD",availability_domain="AD-1",tenancy_limit=64,resource_availability={status="observed",available=64}}]},capacity={region="region-one",availability_domains=[{name="AD-1",assessment={observed_at="test",shapes=[{shape="BM.GPU.H100.8",available_instances=2,availability_status="AVAILABLE"}]}}]}}]
}
override_data {
 target=data.http.recipe_metadata[0]
 values={status_code=200,response_body="{\"model\": {\"model_id\": \"RecursiveSI/flint\", \"context_length\": 262144}, \"variants\": {\"default\": {\"precision\": \"bf16\", \"vram_minimum_gb\": 96}}, \"meta\": {\"tasks\": [\"text\"]}}"}
}
override_data {
 target=data.http.recipe_rendering["hardware=h100&variant=default&strategy=single_node_tp"]
 values={status_code=200,response_body="{\"hf_id\": \"RecursiveSI/flint\", \"hardware\": \"h100\", \"strategy\": \"single_node_tp\", \"variant\": \"default\", \"node_count\": 1, \"deploy_type\": \"single_node\", \"env\": {}, \"docker_image\": \"vllm/vllm-openai:latest\", \"command\": \"vllm serve RecursiveSI/flint \\\\\\n  --tensor-parallel-size 1 \\\\\\n  --enable-auto-tool-choice \\\\\\n  --tool-call-parser glm47 \\\\\\n  --exclude-tools-when-tool-choice-none \\\\\\n  --reasoning-parser glm47\", \"argv\": [\"vllm\", \"serve\", \"RecursiveSI/flint\", \"--tensor-parallel-size\", \"1\", \"--enable-auto-tool-choice\", \"--tool-call-parser\", \"glm47\", \"--exclude-tools-when-tool-choice-none\", \"--reasoning-parser\", \"glm47\"], \"docker_command\": \"docker run --gpus all \\\\\\n  --privileged --ipc=host -p 8000:8000 \\\\\\n  -v ~/.cache/huggingface:/root/.cache/huggingface \\\\\\n  vllm/vllm-openai:latest RecursiveSI/flint \\\\\\n  --tensor-parallel-size 1 \\\\\\n  --enable-auto-tool-choice \\\\\\n  --tool-call-parser glm47 \\\\\\n  --exclude-tools-when-tool-choice-none \\\\\\n  --reasoning-parser glm47\", \"docker_argv\": [\"docker\", \"run\", \"--gpus\", \"all\", \"--privileged\", \"--ipc=host\", \"-p\", \"8000:8000\", \"-v\", \"~/.cache/huggingface:/root/.cache/huggingface\", \"vllm/vllm-openai:latest\", \"RecursiveSI/flint\", \"--tensor-parallel-size\", \"1\", \"--enable-auto-tool-choice\", \"--tool-call-parser\", \"glm47\", \"--exclude-tools-when-tool-choice-none\", \"--reasoning-parser\", \"glm47\"], \"selection\": {\"hardware\": \"h100\", \"variant\": \"default\", \"strategy\": \"single_node_tp\", \"nodes\": 1, \"features\": [\"tool_calling\", \"reasoning\"], \"modes\": {}, \"advanced\": [], \"frontend\": \"python\", \"kv_offload\": null, \"pd\": null, \"preset\": null, \"point\": null, \"adjusted\": []}, \"page_url\": \"https://recipes.vllm.ai/RecursiveSI/flint?hardware=h100&variant=default&strategy=single_node_tp\", \"markdown_url\": \"https://recipes.vllm.ai/RecursiveSI/flint.md?hardware=h100&variant=default&strategy=single_node_tp\"}"}
}
override_data {
 target=data.http.recipe_image["vllm/vllm-openai:latest"]
 values={status_code=200,response_body="{\"images\": [{\"os\": \"linux\", \"architecture\": \"amd64\", \"digest\": \"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"}]}"}
}
run "Flint_H100_adapts_TP_instead_of_copying_an_undersized_rendering" {
 command=plan
 assert {
  condition=output.assessment.suggestions[0].tensor_parallel_size==2 && output.assessment.suggestions[0].configuration_origin=="adapted_recipe" && contains(output.assessment.suggestions[0].serving_configuration.recipe.args,"glm47") && output.assessment.suggestions[0].upstream_validation=="not_established_for_this_configuration"
  error_message="Flint BF16 must retain its flags but suggest TP2 rather than blindly copying TP1 into an undersized H100 memory budget."
 }
}

run "NVFP4_keeps_its_checkpoint_and_exposes_config_staging_requirements" {
 command=plan
 variables {
  regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="BM.GPU.B200.8",gpus=8,rdma_ports=0,quota_names=["gpu-count"]}]}],limits=[{name="gpu-count",description="GPUs for test instances",scope_type="AD",availability_domain="AD-1",tenancy_limit=64,resource_availability={status="observed",available=64}}]},capacity={region="region-one",availability_domains=[{name="AD-1",assessment={observed_at="test",shapes=[{shape="BM.GPU.B200.8",available_instances=1,availability_status="AVAILABLE"}]}}]}}]
  profile={model={repository="RecursiveSI/flint-nvfp4-gguf",resolved_revision="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",pipeline_tag="text-generation",chat_template_available=true,config_sources={config_repository="RecursiveSI/flint"}},architecture={architectures=["FlintForCausalLM"],attention={heads=32,kv_heads=4}},memory={status="unsupported",runtime_allowance_bytes=2147483648,assumptions={context_length=4096,concurrency=4,kv_dtype="bfloat16"},reasons=["GGUF resident memory unknown"]}}
 }
 override_data {
 target=data.http.recipe_metadata[0]
 values={status_code=200,response_body="{\"model\": {\"model_id\": \"RecursiveSI/flint-nvfp4-gguf\", \"context_length\": 262144}, \"variants\": {\"default\": {\"precision\": \"bf16\", \"vram_minimum_gb\": 96}, \"nvfp4\": {\"model_id\": \"RecursiveSI/flint-nvfp4-gguf\", \"precision\": \"nvfp4\", \"vram_minimum_gb\": 29}}, \"meta\": {\"tasks\": [\"text\"]}, \"recommended_command\": {\"variant\": \"nvfp4\"}}"}
 }
 override_data {
 target=data.http.recipe_rendering["hardware=b200&variant=nvfp4&strategy=single_node_tp"]
 values={status_code=200,response_body="{\"hf_id\": \"RecursiveSI/flint\", \"hardware\": \"b200\", \"strategy\": \"single_node_tp\", \"variant\": \"nvfp4\", \"node_count\": 1, \"deploy_type\": \"single_node\", \"env\": {}, \"docker_image\": \"vllm/vllm-openai:latest\", \"command\": \"vllm serve RecursiveSI/flint-nvfp4-gguf \\\\\\n  --hf-config-path RecursiveSI/flint \\\\\\n  --tokenizer RecursiveSI/flint \\\\\\n  --tensor-parallel-size 1 \\\\\\n  --enable-auto-tool-choice \\\\\\n  --tool-call-parser glm47 \\\\\\n  --exclude-tools-when-tool-choice-none \\\\\\n  --reasoning-parser glm47\", \"argv\": [\"vllm\", \"serve\", \"RecursiveSI/flint-nvfp4-gguf\", \"--hf-config-path\", \"RecursiveSI/flint\", \"--tokenizer\", \"RecursiveSI/flint\", \"--tensor-parallel-size\", \"1\", \"--enable-auto-tool-choice\", \"--tool-call-parser\", \"glm47\", \"--exclude-tools-when-tool-choice-none\", \"--reasoning-parser\", \"glm47\"], \"docker_command\": \"docker run --gpus all \\\\\\n  --privileged --ipc=host -p 8000:8000 \\\\\\n  -v ~/.cache/huggingface:/root/.cache/huggingface \\\\\\n  vllm/vllm-openai:latest RecursiveSI/flint-nvfp4-gguf \\\\\\n  --hf-config-path RecursiveSI/flint \\\\\\n  --tokenizer RecursiveSI/flint \\\\\\n  --tensor-parallel-size 1 \\\\\\n  --enable-auto-tool-choice \\\\\\n  --tool-call-parser glm47 \\\\\\n  --exclude-tools-when-tool-choice-none \\\\\\n  --reasoning-parser glm47\", \"docker_argv\": [\"docker\", \"run\", \"--gpus\", \"all\", \"--privileged\", \"--ipc=host\", \"-p\", \"8000:8000\", \"-v\", \"~/.cache/huggingface:/root/.cache/huggingface\", \"vllm/vllm-openai:latest\", \"RecursiveSI/flint-nvfp4-gguf\", \"--hf-config-path\", \"RecursiveSI/flint\", \"--tokenizer\", \"RecursiveSI/flint\", \"--tensor-parallel-size\", \"1\", \"--enable-auto-tool-choice\", \"--tool-call-parser\", \"glm47\", \"--exclude-tools-when-tool-choice-none\", \"--reasoning-parser\", \"glm47\"], \"selection\": {\"hardware\": \"b200\", \"variant\": \"nvfp4\", \"strategy\": \"single_node_tp\", \"nodes\": 1, \"features\": [\"tool_calling\", \"reasoning\"], \"modes\": {}, \"advanced\": [], \"frontend\": \"python\", \"kv_offload\": null, \"pd\": null, \"preset\": null, \"point\": null, \"adjusted\": []}, \"page_url\": \"https://recipes.vllm.ai/RecursiveSI/flint?hardware=b200&variant=nvfp4&strategy=single_node_tp\", \"markdown_url\": \"https://recipes.vllm.ai/RecursiveSI/flint.md?hardware=b200&variant=nvfp4&strategy=single_node_tp\"}"}
 }

 assert {
  condition=output.assessment.suggestions[0].tensor_parallel_size==1 && length(output.assessment.suggestions[0].deployment_requirements)==1 && contains(output.assessment.suggestions[0].serving_configuration.recipe.args,"--hf-config-path") && output.assessment.suggestions[0].serving_configuration.model.repository=="RecursiveSI/flint-nvfp4-gguf"
  error_message="The NVFP4 option must retain its own model/config flags and explicit staging requirement, without claiming a ready validated launch."
 }
}

run "quota_must_cover_the_full_eight_GPU_host_even_for_TP2" {
 command=plan
 variables {
  regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="BM.GPU.H100.8",gpus=8,rdma_ports=0,quota_names=["gpu-count"]}]}],limits=[{name="gpu-count",description="GPUs for test instances",scope_type="AD",availability_domain="AD-1",tenancy_limit=64,resource_availability={status="observed",available=4}}]},capacity={region="region-one",availability_domains=[{name="AD-1",assessment={observed_at="test",shapes=[{shape="BM.GPU.H100.8",available_instances=2,availability_status="AVAILABLE"}]}}]}}]
 }
 assert {
  condition=length(output.assessment.suggestions)==0 && output.assessment.shape_observations[0].entitled_instances==0
  error_message="Headroom for four GPUs cannot allocate an eight-GPU node even when the model only needs TP2."
 }
}

run "recipe_suggestions_pack_replicas_using_confirmed_full_host_quantities" {
  command = plan
  variables { replicas = 5 }
  assert {
    condition = length(output.assessment.suggestions) == 1 && output.assessment.suggestions[0].tensor_parallel_size == 2 && output.assessment.suggestions[0].replicas_per_node == 4 && output.assessment.suggestions[0].node_count == 2 && output.assessment.suggestions[0].replicas == 8 && output.assessment.suggestions[0].requested_minimum_replicas == 5 && output.assessment.shape_observations[0].eligible_at_scan
    error_message = "Five requested TP2 replicas need two eight-GPU hosts; fill eight fixed replica slots without requiring five hosts."
  }
}

run "recipe_packing_does_not_exceed_reported_host_capacity" {
  command = plan
  variables { replicas = 9 }
  assert {
    condition = length(output.assessment.suggestions) == 0
    error_message = "Nine TP2 replicas require three complete hosts, exceeding the two-host capacity observation."
  }
}
