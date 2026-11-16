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
  regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="BM.GPU.A10.4",gpus=4,rdma_ports=0,quota_names=["gpu-count"]}]}],limits=[{name="gpu-count",description="GPUs for test instances",scope_type="AD",availability_domain="AD-1",tenancy_limit=64,resource_availability={status="observed",available=64}}]},capacity={region="region-one",availability_domains=[{name="AD-1",assessment={observed_at="test",shapes=[{shape="BM.GPU.A10.4",available_instances=1,availability_status="AVAILABLE"}]}}]}}]
}
override_data {
 target = data.http.recipe_metadata[0]
 values = {status_code=200,response_body="{\"model\": {\"model_id\": \"Qwen/Qwen3.8-27B\", \"install\": {\"extras\": [{\"command\": \"uv pip install \\\"transformers>=5.8.0\\\"\"}]}}, \"variants\": {\"default\": {\"precision\": \"bf16\", \"vram_minimum_gb\": 67}}, \"meta\": {\"tasks\": [\"text\", \"multimodal\"]}}"}
}
override_data {
 target = data.http.recipe_rendering["hardware=h100&variant=default&strategy=single_node_tp"]
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
run "unselected_cache_alternatives_do_not_make_requests" {
 command=plan
 override_data {
  target=data.http.recipe_metadata[0]
  values={status_code=200,response_body="{\"model\":{\"model_id\":\"Qwen/Qwen3.8-27B\"},\"variants\":{\"default\":{\"precision\":\"bf16\",\"vram_minimum_gb\":67}},\"meta\":{\"tasks\":[\"text\"]},\"kv_offload_support\":{\"offloading_cpu\":\"verified\"}}"}
 }
 assert {
  condition=length(data.http.cache_option)==0 && length(output.assessment.recipe_options.cache_options)==0 && length(output.assessment.suggestions)==1
  error_message="Normal recipe discovery must not fetch unused cache alternatives merely because the model supports offloading."
 }
}
run "declared_non_text_recipe_tasks_are_preserved_without_a_false_smoke_claim" {
 command=plan
 override_data {
  target=data.http.recipe_metadata[0]
  values={status_code=200,response_body="{\"model\":{\"model_id\":\"Qwen/Qwen3.8-27B\"},\"variants\":{\"default\":{\"precision\":\"bf16\",\"vram_minimum_gb\":67}},\"meta\":{\"tasks\":[\"audio\"]}}"}
 }
 assert {
  condition=length(output.assessment.suggestions)==1 && output.assessment.suggestions[0].serving_configuration.recipe.serving_tasks==["audio"] && output.assessment.suggestions[0].serving_configuration.recipe.modality_validation=="not_run_requires_task_specific_validation"
  error_message="A supplied recipe rendering must not be rejected solely because it lacks the text task, or claim text smoke tests validate other modalities."
 }
}
run "shared_full_queries_are_requested_once_with_hardware_fit_ranking" {
 command=plan
 variables {
  replicas=5
  assess_cache_alternatives=true
  regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="BM.GPU.A10.4",gpus=4,rdma_ports=0,quota_names=["gpu-count"]},{shape="BM.GPU.H100.8",gpus=8,rdma_ports=0,quota_names=["gpu-count"]}]}],limits=[{name="gpu-count",description="GPUs for test instances",scope_type="AD",availability_domain="AD-1",tenancy_limit=64,resource_availability={status="observed",available=64}}]},capacity={region="region-one",availability_domains=[{name="AD-1",assessment={observed_at="test",shapes=[{shape="BM.GPU.A10.4",available_instances=5,availability_status="AVAILABLE"},{shape="BM.GPU.H100.8",available_instances=5,availability_status="AVAILABLE"}]}}]}}]
 }
 override_data {
  target=data.http.recipe_metadata[0]
  values={status_code=200,response_body="{\"model\":{\"model_id\":\"Qwen/Qwen3.8-27B\"},\"variants\":{\"default\":{\"precision\":\"bf16\",\"vram_minimum_gb\":67}},\"meta\":{\"tasks\":[\"text\"]},\"kv_offload_support\":{\"offloading_cpu\":\"verified\"}}"}
 }
 override_data {
  target=data.http.cache_option["hardware=h100&variant=default&strategy=single_node_tp&kv_offload=simple"]
  values={status_code=404,response_body="{}"}
 }
 override_data {
  target=data.http.cache_option["hardware=h100&variant=default&strategy=single_node_tp&kv_offload=lmcache"]
  values={status_code=404,response_body="{}"}
 }
 assert {
  condition=length(data.http.recipe_rendering)==1 && length(data.http.cache_option)==2 && length(output.assessment.suggestions)==2 && output.assessment.suggestions[0].gpu_shape=="BM.GPU.H100.8" && output.assessment.suggestions[0].node_count==1 && output.assessment.suggestions[1].node_count==5
  error_message="A10 and H100 share one exact render request and two distinct cache queries. Hardware fit prefers the larger-memory H100; request deduplication must remain unchanged."
 }
}
run "an_exact_previously_resolved_image_tag_does_not_repeat_registry_lookup" {
 command=plan
 variables {
  serving_resolution={engine={platform="linux/amd64",image="fixture",image_tag="qwen38",available_images={"linux/amd64"="vllm/vllm-openai@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"},id="stable",version="0.33.0",architectures=["Qwen3_5ForConditionalGeneration"],gpu_compute_capabilities=[86,90],multi_node_backend="mp"},recipe={feature_options={},compatible_strategies=["single_node_tp"]}}
 }
 assert {
  condition=length(data.http.recipe_image)==0 && output.assessment.suggestions[0].serving_configuration.engine.image=="vllm/vllm-openai@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  error_message="Reuse immutable platform digests only when the renderer requests the exact already-resolved repository/tag; do not repeat that registry HTTP request."
 }
}
run "one_a10_is_not_a_bf16_suggestion" {
 command=plan
 variables {
  regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="VM.GPU.A10.1",gpus=1,rdma_ports=0,quota_names=["gpu-count"]}]}],limits=[{name="gpu-count",description="GPUs for test instances",scope_type="AD",availability_domain="AD-1",tenancy_limit=64,resource_availability={status="observed",available=64}}]},capacity={region="region-one",availability_domains=[]}}]
 }
 assert {
  condition=length(output.assessment.suggestions)==0 && length(output.assessment.sizing_diagnostics)==1
  error_message="Do not present a one-card configuration when even the heuristic weight/runtime budget cannot fit."
 }
}
run "API_substitution_does_not_become_a_recipe_match" {
 command=plan
 override_data {
  target=data.http.recipe_rendering["hardware=h100&variant=default&strategy=single_node_tp"]
  values={status_code=200,response_body="{\"hf_id\": \"Qwen/Qwen3.8-27B\", \"hardware\": \"h100\", \"strategy\": \"single_node_tp\", \"variant\": \"default\", \"node_count\": 1, \"deploy_type\": \"single_node\", \"env\": {\"VLLM_USE_RUST_FRONTEND\": \"1\"}, \"docker_image\": \"vllm/vllm-openai:qwen38\", \"command\": \"vllm serve Qwen/Qwen3.8-27B \\\\\\n  --tensor-parallel-size 1 \\\\\\n  --enable-auto-tool-choice \\\\\\n  --tool-call-parser qwen3_coder \\\\\\n  --reasoning-parser qwen3 \\\\\\n  --mm-encoder-tp-mode data\", \"argv\": [\"vllm\", \"serve\", \"Qwen/Qwen3.8-27B\", \"--tensor-parallel-size\", \"1\", \"--enable-auto-tool-choice\", \"--tool-call-parser\", \"qwen3_coder\", \"--reasoning-parser\", \"qwen3\", \"--mm-encoder-tp-mode\", \"data\"], \"docker_command\": \"docker run --gpus all \\\\\\n  --privileged --ipc=host -p 8000:8000 \\\\\\n  -v ~/.cache/huggingface:/root/.cache/huggingface \\\\\\n  -e VLLM_USE_RUST_FRONTEND=1 \\\\\\n  vllm/vllm-openai:qwen38 Qwen/Qwen3.8-27B \\\\\\n  --tensor-parallel-size 1 \\\\\\n  --enable-auto-tool-choice \\\\\\n  --tool-call-parser qwen3_coder \\\\\\n  --reasoning-parser qwen3 \\\\\\n  --mm-encoder-tp-mode data\", \"docker_argv\": [\"docker\", \"run\", \"--gpus\", \"all\", \"--privileged\", \"--ipc=host\", \"-p\", \"8000:8000\", \"-v\", \"~/.cache/huggingface:/root/.cache/huggingface\", \"-e\", \"VLLM_USE_RUST_FRONTEND=1\", \"vllm/vllm-openai:qwen38\", \"Qwen/Qwen3.8-27B\", \"--tensor-parallel-size\", \"1\", \"--enable-auto-tool-choice\", \"--tool-call-parser\", \"qwen3_coder\", \"--reasoning-parser\", \"qwen3\", \"--mm-encoder-tp-mode\", \"data\"], \"selection\": {\"hardware\": \"h200\", \"variant\": \"default\", \"strategy\": \"single_node_tp\", \"nodes\": 1, \"features\": [\"tool_calling\", \"reasoning\", \"encoder_parallel\"], \"modes\": {\"spec_decoding\": \"mtp\"}, \"advanced\": [], \"frontend\": \"rust\", \"kv_offload\": null, \"pd\": null, \"preset\": null, \"point\": null, \"adjusted\": [{\"param\": \"hardware\", \"requested\": \"h100\", \"used\": \"h200\"}]}, \"page_url\": \"https://recipes.vllm.ai/Qwen/Qwen3.8-27B?hardware=h100&variant=default&strategy=single_node_tp\", \"markdown_url\": \"https://recipes.vllm.ai/Qwen/Qwen3.8-27B.md?hardware=h100&variant=default&strategy=single_node_tp\"}"}
 }
 assert {
  condition=length(output.assessment.suggestions)==0 && output.assessment.recipe_api_diagnostics.a10.hardware=="h200"
  error_message="Adjusted API selections must be retained as diagnostics, not offered as matching configurations."
 }
}

run "known_unsupported_precision_is_not_adapted_to_A10" {
 command=plan
 override_data {
  target=data.http.recipe_metadata[0]
  values={status_code=200,response_body="{\"model\":{\"model_id\":\"Qwen/Qwen3.8-27B\"},\"variants\":{\"default\":{\"precision\":\"nvfp4\",\"vram_minimum_gb\":32,\"supported_hardware\":[\"b200\"]}},\"meta\":{\"tasks\":[\"text\"]}}"}
 }
 assert {
  condition=length(output.assessment.suggestions)==0
  error_message="NVFP4 hardware-specific requirements must not be bypassed by an A10/H100 baseline adaptation."
 }
}

run "cache_companion_plans_are_preserved_without_enabling_them" {
 command=plan
 variables { assess_cache_alternatives = true }
 override_data {
 target=data.http.recipe_metadata[0]
 values={status_code=200,response_body="{\"model\": {\"model_id\": \"Qwen/Qwen3.8-27B\"}, \"variants\": {\"default\": {\"precision\": \"bf16\", \"vram_minimum_gb\": 67}}, \"meta\": {\"tasks\": [\"text\"]}, \"kv_offload_support\": {\"offloading_cpu\": \"verified\"}}"}
 }
 override_data {
 target=data.http.cache_option["hardware=h100&variant=default&strategy=single_node_tp&kv_offload=lmcache"]
 values={status_code=200,response_body="{\"hf_id\": \"Qwen/Qwen3.8-27B\", \"hardware\": \"h100\", \"strategy\": \"single_node_tp\", \"variant\": \"default\", \"node_count\": 1, \"deploy_type\": \"single_node\", \"env\": {\"VLLM_USE_RUST_FRONTEND\": \"1\"}, \"docker_image\": \"vllm/vllm-openai:qwen38\", \"command\": \"vllm serve Qwen/Qwen3.8-27B \\\\\\n  --tensor-parallel-size 1 \\\\\\n  --enable-auto-tool-choice \\\\\\n  --tool-call-parser qwen3_coder \\\\\\n  --reasoning-parser qwen3 \\\\\\n  --kv-transfer-config '{\\\"kv_connector\\\":\\\"LMCacheMPConnector\\\",\\\"kv_role\\\":\\\"kv_both\\\",\\\"kv_connector_extra_config\\\":{\\\"lmcache.mp.port\\\":5555,\\\"lmcache.mp.mq_timeout\\\":300}}'\", \"argv\": [\"vllm\", \"serve\", \"Qwen/Qwen3.8-27B\", \"--tensor-parallel-size\", \"1\", \"--enable-auto-tool-choice\", \"--tool-call-parser\", \"qwen3_coder\", \"--reasoning-parser\", \"qwen3\", \"--kv-transfer-config\", \"{\\\"kv_connector\\\":\\\"LMCacheMPConnector\\\",\\\"kv_role\\\":\\\"kv_both\\\",\\\"kv_connector_extra_config\\\":{\\\"lmcache.mp.port\\\":5555,\\\"lmcache.mp.mq_timeout\\\":300}}\"], \"kv_offload_install\": [{\"command\": \"uv pip install \\\"lmcache==0.5.1\\\"\"}], \"docker_command\": \"docker run --gpus all \\\\\\n  --privileged --ipc=host -p 8000:8000 \\\\\\n  -v ~/.cache/huggingface:/root/.cache/huggingface \\\\\\n  -e VLLM_USE_RUST_FRONTEND=1 \\\\\\n  vllm/vllm-openai:qwen38 Qwen/Qwen3.8-27B \\\\\\n  --tensor-parallel-size 1 \\\\\\n  --enable-auto-tool-choice \\\\\\n  --tool-call-parser qwen3_coder \\\\\\n  --reasoning-parser qwen3 \\\\\\n  --kv-transfer-config '{\\\"kv_connector\\\":\\\"LMCacheMPConnector\\\",\\\"kv_role\\\":\\\"kv_both\\\",\\\"kv_connector_extra_config\\\":{\\\"lmcache.mp.port\\\":5555,\\\"lmcache.mp.mq_timeout\\\":300}}'\", \"docker_argv\": [\"docker\", \"run\", \"--gpus\", \"all\", \"--privileged\", \"--ipc=host\", \"-p\", \"8000:8000\", \"-v\", \"~/.cache/huggingface:/root/.cache/huggingface\", \"-e\", \"VLLM_USE_RUST_FRONTEND=1\", \"vllm/vllm-openai:qwen38\", \"Qwen/Qwen3.8-27B\", \"--tensor-parallel-size\", \"1\", \"--enable-auto-tool-choice\", \"--tool-call-parser\", \"qwen3_coder\", \"--reasoning-parser\", \"qwen3\", \"--kv-transfer-config\", \"{\\\"kv_connector\\\":\\\"LMCacheMPConnector\\\",\\\"kv_role\\\":\\\"kv_both\\\",\\\"kv_connector_extra_config\\\":{\\\"lmcache.mp.port\\\":5555,\\\"lmcache.mp.mq_timeout\\\":300}}\"], \"companions\": [{\"feature\": \"kv_offload:lmcache\", \"label\": \"LMCache Server\", \"description\": \"Run on the same node in a separate terminal, before vllm serve \\u2014 owns the shared CPU-DRAM KV pool. Requires: uv pip install \\\"lmcache==0.5.1\\\"\", \"command\": \"# --port must match \\\"lmcache.mp.port\\\" in --kv-transfer-config.\\n# Size --l1-size-gb to ~75% of the host DRAM you can dedicate \\u2014 pinned\\n# memory is unswappable; the pool grows lazily from --l1-init-size-gb.\\n# --max-gpu-workers 1 avoids concurrent-GPU-transfer stalls under heavy\\n# async-load pressure; CPU-side workers stay at 8.\\nlmcache server \\\\\\n  --port 5555 \\\\\\n  --http-port 8080 \\\\\\n  --l1-size-gb 512 \\\\\\n  --l1-init-size-gb 20 \\\\\\n  --max-gpu-workers 1 \\\\\\n  --max-cpu-workers 8 \\\\\\n  --chunk-size 1024 \\\\\\n  --l1-align-bytes 16384 \\\\\\n  --eviction-trigger-watermark 0.85 \\\\\\n  --eviction-ratio 0.10 \\\\\\n  --eviction-policy LRU \\\\\\n  --supported-transfer-mode lmcache_driven\"}], \"selection\": {\"hardware\": \"h100\", \"variant\": \"default\", \"strategy\": \"single_node_tp\", \"nodes\": 1, \"features\": [\"tool_calling\", \"reasoning\"], \"modes\": {\"spec_decoding\": \"mtp\"}, \"advanced\": [], \"frontend\": \"rust\", \"kv_offload\": \"lmcache\", \"pd\": null, \"preset\": null, \"point\": null, \"adjusted\": []}, \"page_url\": \"https://recipes.vllm.ai/Qwen/Qwen3.8-27B?hardware=h100&features=tool_calling%2Creasoning&kv_offload=lmcache\", \"markdown_url\": \"https://recipes.vllm.ai/Qwen/Qwen3.8-27B.md?hardware=h100&features=tool_calling%2Creasoning&kv_offload=lmcache\"}"}
 }
 override_data {
 target=data.http.cache_option["hardware=h100&variant=default&strategy=single_node_tp&kv_offload=simple"]
 values={status_code=200,response_body="{\"selection\": {\"hardware\": \"h100\", \"variant\": \"default\", \"kv_offload\": \"simple\"}, \"argv\": [\"vllm\", \"serve\", \"Qwen/Qwen3.8-27B\"]}"}
 }
 assert {
  condition=output.assessment.recipe_options.cache_options["a10/lmcache"].plan.companions[0].label=="LMCache Server" && length(output.assessment.recipe_options.cache_options["a10/lmcache"].plan.kv_offload_install)==1 && !contains(output.assessment.suggestions[0].serving_configuration.recipe.args,"--kv-transfer-config")
  error_message="Companion/dependency commands must remain reviewable evidence without implicitly enabling an undeployed cache service."
 }
}

run "requested_context_and_concurrency_expand_the_heuristic_budget" {
 command=plan
 variables {
  profile={model={repository="Qwen/Qwen3.8-27B",resolved_revision="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",pipeline_tag="image-text-to-text",chat_template_available=true},architecture={architectures=["Qwen3_5ForConditionalGeneration"],attention={layers=64,heads=32,kv_heads=4,head_dim=256}},weights={tensor_data_bytes=55000000000,tensor_elements=27500000000},memory={status="unsupported",runtime_allowance_bytes=2147483648,assumptions={context_length=262144,concurrency=4,kv_dtype="bfloat16"},reasons=["hybrid estimator missing"]}}
 }
 assert {
  condition=length(output.assessment.suggestions)==0
  error_message="A small upstream memory guideline must not hide the requested long-context/concurrency budget."
 }
}

run "exclude_zero_physical_capacity" {
 command=plan
 variables { regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="BM.GPU.A10.4",gpus=4,rdma_ports=0,quota_names=["gpu-count"]}]}],limits=[{name="gpu-count",description="GPUs for test instances",scope_type="AD",availability_domain="AD-1",tenancy_limit=64,resource_availability={status="observed",available=64}}]},capacity={region="region-one",availability_domains=[{name="AD-1",assessment={observed_at="test",shapes=[{shape="BM.GPU.A10.4",available_instances=0,availability_status="OUT_OF_HOST_CAPACITY"}]}}]}}] }
 assert {
 condition=length(output.assessment.suggestions)==0 && length(output.assessment.sizing_options)==0 && output.assessment.recommended_selection_id==null && length(output.assessment.shape_observations)>0
 error_message="Unavailable or unconfirmed hardware must remain diagnostic, never selectable."
 }
 assert {
  condition=length(data.http.recipe_rendering)==0 && length(data.http.recipe_image)==0 && length(data.http.cache_option)==0
  error_message="No hardware renderer, image or cache lookup is needed when physical capacity is zero."
 }
}

run "exclude_missing_physical_capacity" {
 command=plan
 variables { regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="BM.GPU.A10.4",gpus=4,rdma_ports=0,quota_names=["gpu-count"]}]}],limits=[{name="gpu-count",description="GPUs for test instances",scope_type="AD",availability_domain="AD-1",tenancy_limit=64,resource_availability={status="observed",available=64}}]},capacity={region="region-one",availability_domains=[{name="AD-1",assessment={observed_at="test",shapes=[{shape="BM.GPU.A10.4",available_instances=1,availability_status="UNKNOWN"}]}}]}}] }
 assert {
 condition=length(output.assessment.suggestions)==0 && length(output.assessment.sizing_options)==0 && output.assessment.recommended_selection_id==null && length(output.assessment.shape_observations)>0
 error_message="Unavailable or unconfirmed hardware must remain diagnostic, never selectable."
 }
}

run "exclude_insufficient_GPU_headroom" {
 command=plan
 variables { regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="BM.GPU.A10.4",gpus=4,rdma_ports=0,quota_names=["gpu-count"]}]}],limits=[{name="gpu-count",description="GPUs for test instances",scope_type="AD",availability_domain="AD-1",tenancy_limit=64,resource_availability={status="observed",available=3}}]},capacity={region="region-one",availability_domains=[{name="AD-1",assessment={observed_at="test",shapes=[{shape="BM.GPU.A10.4",available_instances=1,availability_status="AVAILABLE"}]}}]}}] }
 assert {
 condition=length(output.assessment.suggestions)==0 && length(output.assessment.sizing_options)==0 && output.assessment.recommended_selection_id==null && length(output.assessment.shape_observations)>0
 error_message="Unavailable or unconfirmed hardware must remain diagnostic, never selectable."
 }
 assert {
  condition=length(data.http.recipe_rendering)==0 && length(data.http.recipe_image)==0
  error_message="Do not resolve configurations for hardware whose entitlement cannot cover one complete host."
 }
}

run "exclude_unknown_quota_units" {
 command=plan
 variables { regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="BM.GPU.A10.4",gpus=4,rdma_ports=0,quota_names=["gpu-count"]}]}],limits=[{name="gpu-count",description="Instances or cores (unspecified)",scope_type="AD",availability_domain="AD-1",tenancy_limit=64,resource_availability={status="observed",available=64}}]},capacity={region="region-one",availability_domains=[{name="AD-1",assessment={observed_at="test",shapes=[{shape="BM.GPU.A10.4",available_instances=1,availability_status="AVAILABLE"}]}}]}}] }
 assert {
 condition=length(output.assessment.suggestions)==0 && length(output.assessment.sizing_options)==0 && output.assessment.recommended_selection_id==null && length(output.assessment.shape_observations)>0
 error_message="Unavailable or unconfirmed hardware must remain diagnostic, never selectable."
 }
}

run "exclude_missing_headroom" {
 command=plan
 variables { regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="BM.GPU.A10.4",gpus=4,rdma_ports=0,quota_names=["gpu-count"]}]}],limits=[{name="gpu-count",description="GPUs for test instances",scope_type="AD",availability_domain="AD-1",tenancy_limit=64,resource_availability={status="unknown",available=null}}]},capacity={region="region-one",availability_domains=[{name="AD-1",assessment={observed_at="test",shapes=[{shape="BM.GPU.A10.4",available_instances=1,availability_status="AVAILABLE"}]}}]}}] }
 assert {
 condition=length(output.assessment.suggestions)==0 && length(output.assessment.sizing_options)==0 && output.assessment.recommended_selection_id==null && length(output.assessment.shape_observations)>0
 error_message="Unavailable or unconfirmed hardware must remain diagnostic, never selectable."
 }
}

run "exclude_wrong_AD_limits" {
 command=plan
 variables { regions=[{inventory={region="region-one",availability_domains=[{name="AD-1",shapes=[{shape="BM.GPU.A10.4",gpus=4,rdma_ports=0,quota_names=["gpu-count"]}]}],limits=[{name="gpu-count",description="GPUs for test instances",scope_type="AD",availability_domain="AD-2",tenancy_limit=64,resource_availability={status="observed",available=64}}]},capacity={region="region-one",availability_domains=[{name="AD-1",assessment={observed_at="test",shapes=[{shape="BM.GPU.A10.4",available_instances=1,availability_status="AVAILABLE"}]}}]}}] }
 assert {
 condition=length(output.assessment.suggestions)==0 && length(output.assessment.sizing_options)==0 && output.assessment.recommended_selection_id==null && length(output.assessment.shape_observations)>0
 error_message="Unavailable or unconfirmed hardware must remain diagnostic, never selectable."
 }
}

run "replicas_require_enough_full_hosts_and_GPU_entitlement" {
 command=plan
 variables {replicas=2}
 assert {
 condition=length(output.assessment.suggestions)==0
 error_message="A single available host cannot confirm two replicas."
 }
}
run "recipe_companions_and_unknown_features_remain_explicit_in_the_platform_plan" {
  command = plan
  override_data {
    target = data.http.recipe_rendering["hardware=h100&variant=default&strategy=single_node_tp"]
    values = { status_code = 200, response_body = "{\"selection\":{\"hardware\":\"h100\",\"variant\":\"default\",\"strategy\":\"single_node_tp\",\"features\":[\"tool_calling\",\"future_feature\"],\"modes\":{\"spec_decoding\":\"mtp\"},\"kv_offload\":\"lmcache\",\"pd\":null,\"adjusted\":[]},\"argv\":[\"vllm\",\"serve\",\"Qwen/Qwen3.8-27B\",\"--tensor-parallel-size\",\"1\"],\"docker_image\":\"vllm/vllm-openai:qwen38\",\"env\":{},\"kv_offload_install\":[{\"command\":\"uv pip install lmcache==0.5.1\"}],\"companions\":[{\"feature\":\"kv_offload:lmcache\",\"command\":\"lmcache server --l1-size-gb 512\"}]}" }
  }
  assert {
    condition     = length(output.assessment.suggestions) == 1 && output.assessment.suggestions[0].platform_plan.recipe_evidence.companions[0].command == "lmcache server --l1-size-gb 512" && output.assessment.suggestions[0].serving_configuration.recipe.api.rendering.kv_offload_install[0].command == "uv pip install lmcache==0.5.1" && output.assessment.suggestions[0].platform_plan.recipe_evidence.selection.modes.spec_decoding == "mtp" && !output.assessment.suggestions[0].platform_plan.auto_deploy_ready
    error_message = "Keep the complete recipe rendering and companion evidence without executing commands, discarding the option, or treating example host memory as an allocation budget."
  }
  assert {
    condition     = contains([for d in output.assessment.suggestions[0].platform_plan.diagnostics : d.code], "recipe_companion_adapter_required") && contains([for d in output.assessment.suggestions[0].platform_plan.diagnostics : d.code], "feature_integration_unclassified") && output.assessment.suggestions[0].platform_plan.storage_budget.kv_offload_bytes == null
    error_message = "Unsupported companion integration and unclassified features must produce explicit diagnostics and unknown sizing."
  }
}

run "hardware_fit_can_prefer_eight_A100s_over_four_A10s" {
  command = plan
  variables {
    regions = [{ "inventory" : { "region" : "region-one", "availability_domains" : [{ "name" : "AD-1", "shapes" : [{ "shape" : "BM.GPU.A10.4", "gpus" : 4, "rdma_ports" : 0, "quota_names" : ["gpu-count"] }, { "shape" : "BM.GPU.A100-v2.8", "gpus" : 8, "rdma_ports" : 1, "quota_names" : ["gpu-count"] }] }], "limits" : [{ "name" : "gpu-count", "description" : "GPUs for test instances", "scope_type" : "AD", "availability_domain" : "AD-1", "tenancy_limit" : 64, "resource_availability" : { "status" : "observed", "available" : 64 } }] }, "capacity" : { "region" : "region-one", "availability_domains" : [{ "name" : "AD-1", "assessment" : { "observed_at" : "test", "shapes" : [{ "shape" : "BM.GPU.A10.4", "available_instances" : 5, "availability_status" : "AVAILABLE" }, { "shape" : "BM.GPU.A100-v2.8", "available_instances" : 1, "availability_status" : "AVAILABLE" }] } }] } }]

  }
  assert {
    condition     = output.assessment.suggestions[0].gpu_shape == "BM.GPU.A100-v2.8" && output.assessment.suggestions[0].recommendation.gpu_memory_bytes == 80000000000
    error_message = "GPU count is not a performance/cost metric: a larger-memory A100 allocation may rank before four A10s."
  }
}

run "same_hardware_prefers_more_confirmed_growth" {
  command = plan
  variables {
    regions = [{ "inventory" : { "region" : "small", "availability_domains" : [{ "name" : "AD-1", "shapes" : [{ "shape" : "BM.GPU.A10.4", "gpus" : 4, "rdma_ports" : 0, "quota_names" : ["gpu-count"] }] }], "limits" : [{ "name" : "gpu-count", "description" : "GPUs for test instances", "scope_type" : "AD", "availability_domain" : "AD-1", "tenancy_limit" : 64, "resource_availability" : { "status" : "observed", "available" : 64 } }] }, "capacity" : { "region" : "small", "availability_domains" : [{ "name" : "AD-1", "assessment" : { "observed_at" : "test", "shapes" : [{ "shape" : "BM.GPU.A10.4", "available_instances" : 2, "availability_status" : "AVAILABLE" }] } }] } }, { "inventory" : { "region" : "large", "availability_domains" : [{ "name" : "AD-1", "shapes" : [{ "shape" : "BM.GPU.A10.4", "gpus" : 4, "rdma_ports" : 0, "quota_names" : ["gpu-count"] }] }], "limits" : [{ "name" : "gpu-count", "description" : "GPUs for test instances", "scope_type" : "AD", "availability_domain" : "AD-1", "tenancy_limit" : 64, "resource_availability" : { "status" : "observed", "available" : 64 } }] }, "capacity" : { "region" : "large", "availability_domains" : [{ "name" : "AD-1", "assessment" : { "observed_at" : "test", "shapes" : [{ "shape" : "BM.GPU.A10.4", "available_instances" : 6, "availability_status" : "AVAILABLE" }] } }] } }]

  }
  assert {
    condition     = output.assessment.suggestions[0].region == "large" && output.assessment.suggestions[0].recommendation.ad_additional_replicas == 5
    error_message = "Within the same hardware, greater quantity-confirmed AD growth ranks first."
  }
}

run "growth_is_capped_by_entitlement_not_just_physical_hosts" {
  command = plan
  variables {
    regions = [{ "inventory" : { "region" : "usable", "availability_domains" : [{ "name" : "AD-1", "shapes" : [{ "shape" : "BM.GPU.A10.4", "gpus" : 4, "rdma_ports" : 0, "quota_names" : ["gpu-count"] }] }], "limits" : [{ "name" : "gpu-count", "description" : "GPUs for test instances", "scope_type" : "AD", "availability_domain" : "AD-1", "tenancy_limit" : 64, "resource_availability" : { "status" : "observed", "available" : 64 } }] }, "capacity" : { "region" : "usable", "availability_domains" : [{ "name" : "AD-1", "assessment" : { "observed_at" : "test", "shapes" : [{ "shape" : "BM.GPU.A10.4", "available_instances" : 4, "availability_status" : "AVAILABLE" }] } }] } }, { "inventory" : { "region" : "physical-only", "availability_domains" : [{ "name" : "AD-1", "shapes" : [{ "shape" : "BM.GPU.A10.4", "gpus" : 4, "rdma_ports" : 0, "quota_names" : ["gpu-count"] }] }], "limits" : [{ "name" : "gpu-count", "description" : "GPUs for test instances", "scope_type" : "AD", "availability_domain" : "AD-1", "tenancy_limit" : 64, "resource_availability" : { "status" : "observed", "available" : 8 } }] }, "capacity" : { "region" : "physical-only", "availability_domains" : [{ "name" : "AD-1", "assessment" : { "observed_at" : "test", "shapes" : [{ "shape" : "BM.GPU.A10.4", "available_instances" : 10, "availability_status" : "AVAILABLE" }] } }] } }]

  }
  assert {
    condition     = output.assessment.suggestions[0].region == "usable" && output.assessment.suggestions[0].recommendation.ad_max_replicas == 4 && output.assessment.suggestions[1].recommendation.ad_max_replicas == 2
    error_message = "Ten physical hosts with entitlement for two must not outrank four currently usable hosts."
  }
}

run "same_GPU_prefers_RDMA_capability" {
  command = plan
  variables {
    regions     = [{ "inventory" : { "region" : "region-one", "availability_domains" : [{ "name" : "AD-1", "shapes" : [{ "shape" : "GPU.PCIE", "gpus" : 8, "rdma_ports" : 0, "quota_names" : ["gpu-count"] }, { "shape" : "GPU.RDMA", "gpus" : 8, "rdma_ports" : 1, "quota_names" : ["gpu-count"] }] }], "limits" : [{ "name" : "gpu-count", "description" : "GPUs for test instances", "scope_type" : "AD", "availability_domain" : "AD-1", "tenancy_limit" : 64, "resource_availability" : { "status" : "observed", "available" : 64 } }] }, "capacity" : { "region" : "region-one", "availability_domains" : [{ "name" : "AD-1", "assessment" : { "observed_at" : "test", "shapes" : [{ "shape" : "GPU.PCIE", "available_instances" : 8, "availability_status" : "AVAILABLE" }, { "shape" : "GPU.RDMA", "available_instances" : 1, "availability_status" : "AVAILABLE" }] } }] } }]
    gpu_catalog = { "GPU.PCIE" : { "gpus" : 8, "memory_bytes_per_gpu" : 80000000000, "compute_capability" : 80, "recipe_hardware" : "a100-80gb", "cpu_architecture" : "amd64", "compute_cluster_supported" : false, "rdma" : false }, "GPU.RDMA" : { "gpus" : 8, "memory_bytes_per_gpu" : 80000000000, "compute_capability" : 80, "recipe_hardware" : "a100-80gb", "cpu_architecture" : "amd64", "compute_cluster_supported" : false, "rdma" : true } }
  }
  assert {
    condition     = output.assessment.suggestions[0].gpu_shape == "GPU.RDMA" && output.assessment.suggestions[0].recommendation.rdma_capable
    error_message = "For the same GPU and sharding, prefer RDMA-capable hardware without claiming fabric placement is reserved."
  }
}

run "budget_explains_hybrid_surrogate_instead_of_claiming_full_estimate" {
  command = plan
  variables {
    regions = [{ "inventory" : { "region" : "region-one", "availability_domains" : [{ "name" : "AD-1", "shapes" : [{ "shape" : "BM.GPU.A10.4", "gpus" : 4, "rdma_ports" : 0, "quota_names" : ["gpu-count"] }] }], "limits" : [{ "name" : "gpu-count", "description" : "GPUs for test instances", "scope_type" : "AD", "availability_domain" : "AD-1", "tenancy_limit" : 64, "resource_availability" : { "status" : "observed", "available" : 64 } }] }, "capacity" : { "region" : "region-one", "availability_domains" : [{ "name" : "AD-1", "assessment" : { "observed_at" : "test", "shapes" : [{ "shape" : "BM.GPU.A10.4", "available_instances" : 1, "availability_status" : "AVAILABLE" }] } }] } }]
    profile = { "model" : { "repository" : "Qwen/Qwen3.8-27B", "resolved_revision" : "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "pipeline_tag" : "image-text-to-text", "chat_template_available" : true }, "architecture" : { "architectures" : ["Qwen3_5ForConditionalGeneration"], "attention" : { "layers" : 64, "heads" : 24, "kv_heads" : 4, "head_dim" : 256 } }, "weights" : { "tensor_data_bytes" : 55562855904, "tensor_elements" : 27781427952 }, "memory" : { "status" : "unsupported", "runtime_allowance_bytes" : 2147483648, "assumptions" : { "context_length" : 4096, "concurrency" : 4, "kv_dtype" : "bfloat16", "safety_margin_fraction" : 0.2 }, "reasons" : ["hybrid allocation unknown"] } }
  }
  assert {
    condition     = output.assessment.recipe_options.memory_budget_breakdown.weight_bytes == 55562855904 && output.assessment.recipe_options.memory_budget_breakdown.kv_surrogate_bytes == 4294967296 && output.assessment.recipe_options.memory_budget_bytes == 71829387840 && output.assessment.suggestions[0].tensor_parallel_size == 4
    error_message = "Expose the exact conservative payload and KV surrogate used by GPU sizing; hybrid allocations remain unvalidated."
  }
}

run "same_budget_explains_different_TP_and_replica_packing_on_A100_variants" {
  command = plan
  variables {
    regions = [{ "inventory" : { "region" : "region-one", "availability_domains" : [{ "name" : "AD-1", "shapes" : [{ "shape" : "BM.GPU.A10.4", "gpus" : 4, "rdma_ports" : 0, "quota_names" : ["gpu-count"] }, { "shape" : "BM.GPU4.8", "gpus" : 8, "rdma_ports" : 1, "quota_names" : ["gpu-count"] }, { "shape" : "BM.GPU.A100-v2.8", "gpus" : 8, "rdma_ports" : 1, "quota_names" : ["gpu-count"] }] }], "limits" : [{ "name" : "gpu-count", "description" : "GPUs for test instances", "scope_type" : "AD", "availability_domain" : "AD-1", "tenancy_limit" : 64, "resource_availability" : { "status" : "observed", "available" : 64 } }] }, "capacity" : { "region" : "region-one", "availability_domains" : [{ "name" : "AD-1", "assessment" : { "observed_at" : "test", "shapes" : [{ "shape" : "BM.GPU.A10.4", "available_instances" : 1, "availability_status" : "AVAILABLE" }, { "shape" : "BM.GPU4.8", "available_instances" : 1, "availability_status" : "AVAILABLE" }, { "shape" : "BM.GPU.A100-v2.8", "available_instances" : 1, "availability_status" : "AVAILABLE" }] } }] } }]
    profile = { "model" : { "repository" : "Qwen/Qwen3.8-27B", "resolved_revision" : "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "pipeline_tag" : "image-text-to-text", "chat_template_available" : true }, "architecture" : { "architectures" : ["Qwen3_5ForConditionalGeneration"], "attention" : { "layers" : 64, "heads" : 24, "kv_heads" : 4, "head_dim" : 256 } }, "weights" : { "tensor_data_bytes" : 55562855904, "tensor_elements" : 27781427952 }, "memory" : { "status" : "unsupported", "runtime_allowance_bytes" : 2147483648, "assumptions" : { "context_length" : 4096, "concurrency" : 4, "kv_dtype" : "bfloat16", "safety_margin_fraction" : 0.2 }, "reasons" : ["hybrid allocation unknown"] } }
  }
  assert {
    condition     = length(output.assessment.suggestions) == 3 && output.assessment.suggestions[0].gpu_shape == "BM.GPU.A100-v2.8" && output.assessment.suggestions[0].tensor_parallel_size == 2 && output.assessment.suggestions[0].replicas == 4 && one([for option in output.assessment.suggestions : option.tensor_parallel_size if option.gpu_shape == "BM.GPU4.8"]) == 4 && one([for option in output.assessment.suggestions : option.replicas if option.gpu_shape == "BM.GPU4.8"]) == 2
    error_message = "The same 71.83 GB budget needs TP4 on 24/40 GB devices and TP2 on 80 GB devices; pack complete replicas into the eight-GPU host."
  }
}

run "regional_known_supply_ignores_zero_and_missing_ADs" {
  command = plan
  variables {
    regions = [{
      inventory = {
        region = "region-one"
        availability_domains = [for ad in ["AD-1", "AD-2", "AD-3"] : {name=ad, shapes=[{shape="BM.GPU.A10.4",gpus=4,rdma_ports=0,quota_names=["gpu-count"]}]}]
        limits = [{name="gpu-count",description="GPUs for test instances",scope_type="REGION",availability_domain=null,tenancy_limit=64,resource_availability={status="observed",available=64}}]
      }
      capacity = {region="region-one",availability_domains=[
        {name="AD-1",assessment={observed_at="saved",shapes=[{shape="BM.GPU.A10.4",available_instances=2,availability_status="AVAILABLE"}]}},
        {name="AD-2",assessment={observed_at="saved",shapes=[{shape="BM.GPU.A10.4",available_instances=0,availability_status="OUT_OF_HOST_CAPACITY"}]}},
        {name="AD-3",assessment={observed_at="saved",shapes=[]}}
      ]}
    }]
  }
  assert {
    condition = length(output.assessment.suggestions)==1 && output.assessment.suggestions[0].recommendation.regional_known_hosts==2 && output.assessment.suggestions[0].recommendation.ad_max_replicas==2
    error_message = "An available AD remains selectable with a known-host lower bound when other ADs have zero or missing capacity. Unknown data must not enter sum() as null or become a claimed complete total."
  }
}

run "rendered_service_profile_reaches_selection" {
 command=plan
 override_data {
  target=data.http.recipe_rendering["hardware=h100&variant=default&strategy=single_node_tp"]
  values={status_code=200,response_body="{\"hf_id\": \"Qwen/Qwen3.8-27B\", \"hardware\": \"h100\", \"strategy\": \"single_node_tp\", \"variant\": \"default\", \"node_count\": 1, \"deploy_type\": \"single_node\", \"env\": {\"VLLM_USE_RUST_FRONTEND\": \"1\"}, \"docker_image\": \"vllm/vllm-openai:qwen38\", \"command\": \"vllm serve Qwen/Qwen3.8-27B \\\\\\n  --tensor-parallel-size 1 \\\\\\n  --enable-auto-tool-choice \\\\\\n  --tool-call-parser qwen3_coder \\\\\\n  --reasoning-parser qwen3 \\\\\\n  --mm-encoder-tp-mode data\", \"argv\": [\"vllm\", \"serve\", \"Qwen/Qwen3.8-27B\", \"--tensor-parallel-size\", \"1\", \"--enable-auto-tool-choice\", \"--tool-call-parser\", \"qwen3_coder\", \"--reasoning-parser\", \"qwen3\", \"--mm-encoder-tp-mode\", \"data\"], \"docker_command\": \"docker run --gpus all \\\\\\n  --privileged --ipc=host -p 8000:8000 \\\\\\n  -v ~/.cache/huggingface:/root/.cache/huggingface \\\\\\n  -e VLLM_USE_RUST_FRONTEND=1 \\\\\\n  vllm/vllm-openai:qwen38 Qwen/Qwen3.8-27B \\\\\\n  --tensor-parallel-size 1 \\\\\\n  --enable-auto-tool-choice \\\\\\n  --tool-call-parser qwen3_coder \\\\\\n  --reasoning-parser qwen3 \\\\\\n  --mm-encoder-tp-mode data\", \"docker_argv\": [\"docker\", \"run\", \"--gpus\", \"all\", \"--privileged\", \"--ipc=host\", \"-p\", \"8000:8000\", \"-v\", \"~/.cache/huggingface:/root/.cache/huggingface\", \"-e\", \"VLLM_USE_RUST_FRONTEND=1\", \"vllm/vllm-openai:qwen38\", \"Qwen/Qwen3.8-27B\", \"--tensor-parallel-size\", \"1\", \"--enable-auto-tool-choice\", \"--tool-call-parser\", \"qwen3_coder\", \"--reasoning-parser\", \"qwen3\", \"--mm-encoder-tp-mode\", \"data\"], \"selection\": {\"hardware\": \"h100\", \"variant\": \"default\", \"strategy\": \"single_node_tp\", \"nodes\": 1, \"features\": [\"tool_calling\", \"reasoning\", \"encoder_parallel\"], \"modes\": {\"spec_decoding\": \"mtp\"}, \"advanced\": [], \"frontend\": \"rust\", \"kv_offload\": null, \"pd\": null, \"preset\": null, \"point\": null, \"adjusted\": []}, \"page_url\": \"https://recipes.vllm.ai/Qwen/Qwen3.8-27B?hardware=h100&variant=default&strategy=single_node_tp\", \"markdown_url\": \"https://recipes.vllm.ai/Qwen/Qwen3.8-27B.md?hardware=h100&variant=default&strategy=single_node_tp\", \"deployment_profile\": {\"lmcache\": {\"mode\": \"mp\", \"cpu_memory_gb\": 8, \"chunk_size\": 128}, \"routing\": {\"mode\": \"prefixaware\"}}}"}
 }
 assert {
  condition=output.assessment.suggestions[0].serving_configuration.deployment_profile.lmcache.mode=="mp" && output.assessment.suggestions[0].serving_configuration.deployment_profile.routing.mode=="prefixaware"
  error_message="Frozen model selections must preserve generic cache/routing profiles from recipe rendering."
 }
}
