# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "http" {}
variables {
  recipe_api_enabled = true
  profile = {
    model={repository="Qwen/Qwen3.8-27B",resolved_revision="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",pipeline_tag="image-text-to-text",chat_template_available=true}
    architecture={architectures=["Qwen3_5ForConditionalGeneration"],attention={heads=32,kv_heads=4}}
    memory={status="unsupported",runtime_allowance_bytes=2147483648,assumptions={context_length=4096,concurrency=4,kv_dtype="bfloat16"},reasons=["hybrid estimator missing"]}
  }
  engines=[]
  serving_resolution={engine={platform="linux/amd64",image="fixture",id="stable",version="0.33.0",architectures=["Qwen3_5ForConditionalGeneration"],gpu_compute_capabilities=[86,90],multi_node_backend="mp"},recipe={feature_options={},compatible_strategies=["single_node_tp"]}}
  regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="BM.GPU.A10.4",gpus=4,rdma_ports=0,quota_names=[]}]}],limits=[]},capacity={region="region-one",availability_domains=[{name="AD-1",assessment={observed_at="test",shapes=[{shape="BM.GPU.A10.4",available_instances=1,availability_status="AVAILABLE"}]}}]}}]
}
override_data {
 target = data.http.recipe_metadata[0]
 values = {status_code=200,response_body="{\"model\": {\"model_id\": \"Qwen/Qwen3.8-27B\", \"install\": {\"extras\": [{\"command\": \"uv pip install \\\"transformers>=5.8.0\\\"\"}]}}, \"variants\": {\"default\": {\"precision\": \"bf16\", \"vram_minimum_gb\": 67}}, \"meta\": {\"tasks\": [\"text\", \"multimodal\"]}}"}
}
override_data {
 target = data.http.recipe_rendering["a10"]
 values = {status_code=200,response_body="{\"hf_id\": \"Qwen/Qwen3.8-27B\", \"hardware\": \"h100\", \"strategy\": \"single_node_tp\", \"variant\": \"default\", \"node_count\": 1, \"deploy_type\": \"single_node\", \"env\": {\"VLLM_USE_RUST_FRONTEND\": \"1\"}, \"docker_image\": \"vllm/vllm-openai:qwen38\", \"command\": \"vllm serve Qwen/Qwen3.8-27B \\\\\\n  --tensor-parallel-size 1 \\\\\\n  --enable-auto-tool-choice \\\\\\n  --tool-call-parser qwen3_coder \\\\\\n  --reasoning-parser qwen3 \\\\\\n  --mm-encoder-tp-mode data\", \"argv\": [\"vllm\", \"serve\", \"Qwen/Qwen3.8-27B\", \"--tensor-parallel-size\", \"1\", \"--enable-auto-tool-choice\", \"--tool-call-parser\", \"qwen3_coder\", \"--reasoning-parser\", \"qwen3\", \"--mm-encoder-tp-mode\", \"data\"], \"docker_command\": \"docker run --gpus all \\\\\\n  --privileged --ipc=host -p 8000:8000 \\\\\\n  -v ~/.cache/huggingface:/root/.cache/huggingface \\\\\\n  -e VLLM_USE_RUST_FRONTEND=1 \\\\\\n  vllm/vllm-openai:qwen38 Qwen/Qwen3.8-27B \\\\\\n  --tensor-parallel-size 1 \\\\\\n  --enable-auto-tool-choice \\\\\\n  --tool-call-parser qwen3_coder \\\\\\n  --reasoning-parser qwen3 \\\\\\n  --mm-encoder-tp-mode data\", \"docker_argv\": [\"docker\", \"run\", \"--gpus\", \"all\", \"--privileged\", \"--ipc=host\", \"-p\", \"8000:8000\", \"-v\", \"~/.cache/huggingface:/root/.cache/huggingface\", \"-e\", \"VLLM_USE_RUST_FRONTEND=1\", \"vllm/vllm-openai:qwen38\", \"Qwen/Qwen3.8-27B\", \"--tensor-parallel-size\", \"1\", \"--enable-auto-tool-choice\", \"--tool-call-parser\", \"qwen3_coder\", \"--reasoning-parser\", \"qwen3\", \"--mm-encoder-tp-mode\", \"data\"], \"selection\": {\"hardware\": \"h100\", \"variant\": \"default\", \"strategy\": \"single_node_tp\", \"nodes\": 1, \"features\": [\"tool_calling\", \"reasoning\", \"encoder_parallel\"], \"modes\": {\"spec_decoding\": \"mtp\"}, \"advanced\": [], \"frontend\": \"rust\", \"kv_offload\": null, \"pd\": null, \"preset\": null, \"point\": null, \"adjusted\": []}, \"page_url\": \"https://recipes.vllm.ai/Qwen/Qwen3.8-27B?hardware=h100&variant=default&strategy=single_node_tp\", \"markdown_url\": \"https://recipes.vllm.ai/Qwen/Qwen3.8-27B.md?hardware=h100&variant=default&strategy=single_node_tp\"}"}
}
override_data {
 target = data.http.recipe_image["vllm/vllm-openai:qwen38"]
 values = {status_code=200,response_body="{\"images\": [{\"os\": \"linux\", \"architecture\": \"amd64\", \"digest\": \"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"}]}"}
}
run "adapt_bf16_to_four_a10s_without_a_complete_estimator" {
  command=plan
  assert {
    condition=length(output.assessment.suggestions)==1 && output.assessment.suggestions[0].tensor_parallel_size==4 && output.assessment.suggestions[0].configuration_origin=="adapted_recipe" && output.assessment.suggestions[0].runtime_validation=="not_run"
    error_message="A10 should receive a clearly untested TP4 BF16 suggestion, without pretending it is an upstream A10 rendering."
  }
  assert {
    condition=contains(output.assessment.suggestions[0].serving_configuration.recipe.args,"qwen3_coder") && !contains(output.assessment.suggestions[0].serving_configuration.recipe.args,"--tensor-parallel-size") && output.assessment.suggestions[0].serving_configuration.engine.image=="vllm/vllm-openai@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" && length(output.assessment.suggestions[0].serving_configuration.recipe.dependencies)==1
    error_message="Parsers, image digest and dependency evidence must survive, with topology managed separately."
  }
}
run "one_a10_is_not_a_bf16_suggestion" {
 command=plan
 variables {
  regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="VM.GPU.A10.1",gpus=1,rdma_ports=0,quota_names=[]}]}],limits=[]},capacity={region="region-one",availability_domains=[]}}]
 }
 assert {
  condition=length(output.assessment.suggestions)==0 && length(output.assessment.sizing_options)==1
  error_message="Do not present a one-card configuration when even the heuristic weight/runtime budget cannot fit."
 }
}
run "API_substitution_does_not_become_a_recipe_match" {
 command=plan
 override_data {
  target=data.http.recipe_rendering["a10"]
  values={status_code=200,response_body="{\"hf_id\": \"Qwen/Qwen3.8-27B\", \"hardware\": \"h100\", \"strategy\": \"single_node_tp\", \"variant\": \"default\", \"node_count\": 1, \"deploy_type\": \"single_node\", \"env\": {\"VLLM_USE_RUST_FRONTEND\": \"1\"}, \"docker_image\": \"vllm/vllm-openai:qwen38\", \"command\": \"vllm serve Qwen/Qwen3.8-27B \\\\\\n  --tensor-parallel-size 1 \\\\\\n  --enable-auto-tool-choice \\\\\\n  --tool-call-parser qwen3_coder \\\\\\n  --reasoning-parser qwen3 \\\\\\n  --mm-encoder-tp-mode data\", \"argv\": [\"vllm\", \"serve\", \"Qwen/Qwen3.8-27B\", \"--tensor-parallel-size\", \"1\", \"--enable-auto-tool-choice\", \"--tool-call-parser\", \"qwen3_coder\", \"--reasoning-parser\", \"qwen3\", \"--mm-encoder-tp-mode\", \"data\"], \"docker_command\": \"docker run --gpus all \\\\\\n  --privileged --ipc=host -p 8000:8000 \\\\\\n  -v ~/.cache/huggingface:/root/.cache/huggingface \\\\\\n  -e VLLM_USE_RUST_FRONTEND=1 \\\\\\n  vllm/vllm-openai:qwen38 Qwen/Qwen3.8-27B \\\\\\n  --tensor-parallel-size 1 \\\\\\n  --enable-auto-tool-choice \\\\\\n  --tool-call-parser qwen3_coder \\\\\\n  --reasoning-parser qwen3 \\\\\\n  --mm-encoder-tp-mode data\", \"docker_argv\": [\"docker\", \"run\", \"--gpus\", \"all\", \"--privileged\", \"--ipc=host\", \"-p\", \"8000:8000\", \"-v\", \"~/.cache/huggingface:/root/.cache/huggingface\", \"-e\", \"VLLM_USE_RUST_FRONTEND=1\", \"vllm/vllm-openai:qwen38\", \"Qwen/Qwen3.8-27B\", \"--tensor-parallel-size\", \"1\", \"--enable-auto-tool-choice\", \"--tool-call-parser\", \"qwen3_coder\", \"--reasoning-parser\", \"qwen3\", \"--mm-encoder-tp-mode\", \"data\"], \"selection\": {\"hardware\": \"h200\", \"variant\": \"default\", \"strategy\": \"single_node_tp\", \"nodes\": 1, \"features\": [\"tool_calling\", \"reasoning\", \"encoder_parallel\"], \"modes\": {\"spec_decoding\": \"mtp\"}, \"advanced\": [], \"frontend\": \"rust\", \"kv_offload\": null, \"pd\": null, \"preset\": null, \"point\": null, \"adjusted\": [{\"param\": \"hardware\", \"requested\": \"h100\", \"used\": \"h200\"}]}, \"page_url\": \"https://recipes.vllm.ai/Qwen/Qwen3.8-27B?hardware=h100&variant=default&strategy=single_node_tp\", \"markdown_url\": \"https://recipes.vllm.ai/Qwen/Qwen3.8-27B.md?hardware=h100&variant=default&strategy=single_node_tp\"}"}
 }
 assert {
  condition=length(output.assessment.suggestions)==0 && output.assessment.recipe_api_diagnostics.a10.hardware=="h200"
  error_message="Adjusted API selections must be retained as diagnostics, not offered as matching configurations."
 }
}
