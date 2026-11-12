# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "http" {}
variables {
 recipe_api_enabled=true
 profile={model={repository="RecursiveSI/flint",resolved_revision="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",pipeline_tag="text-generation",chat_template_available=true},architecture={architectures=["FlintForCausalLM"],attention={heads=32,kv_heads=4}},memory={status="unsupported",runtime_allowance_bytes=2147483648,assumptions={context_length=4096,concurrency=4,kv_dtype="bfloat16"},reasons=["hybrid estimator missing"]}}
 engines=[]
 serving_resolution={engine={platform="linux/amd64",image="fixture",version="0.33.0",architectures=["FlintForCausalLM"],gpu_compute_capabilities=[90],multi_node_backend="mp"},recipe={}}
 regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="BM.GPU.H100.8",gpus=8,rdma_ports=0,quota_names=[]}]}],limits=[]},capacity={region="region-one",availability_domains=[]}}]
}
override_data {
 target=data.http.recipe_metadata[0]
 values={status_code=200,response_body="{\"model\": {\"model_id\": \"RecursiveSI/flint\", \"context_length\": 262144}, \"variants\": {\"default\": {\"precision\": \"bf16\", \"vram_minimum_gb\": 96}}, \"meta\": {\"tasks\": [\"text\"]}}"}
}
override_data {
 target=data.http.recipe_rendering["h100"]
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
