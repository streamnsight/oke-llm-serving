# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "http" {}
variables { model="RecursiveSI/flint-nvfp4-gguf" }
override_data {
 target=data.http.model
 values={status_code=200,response_body="{\"sha\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"siblings\":[{\"rfilename\":\"flint.gguf\",\"size\":23000000000}]}"}
}
override_data {
 target=data.http.config
 values={status_code=404,response_body="{}"}
}
override_data {
 target=data.http.card
 values={status_code=404,response_body=""}
}
override_data {
 target=data.http.fallback_recipe[0]
 values={status_code=200,response_body="{\"meta\":{\"tasks\":[\"text\"]},\"variants\":{\"nvfp4\":{\"model_id\":\"RecursiveSI/flint-nvfp4-gguf\",\"extra_args\":[\"--hf-config-path\",\"RecursiveSI/flint\",\"--tokenizer\",\"RecursiveSI/flint\"]}}}"}
}
override_data {
 target=data.http.fallback_model["RecursiveSI/flint"]
 values={status_code=200,response_body="{\"sha\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"}"}
}
override_data {
 target=data.http.fallback_config[0]
 values={status_code=200,response_body="{\"model_type\":\"flint\",\"architectures\":[\"FlintForCausalLM\"],\"num_hidden_layers\":49,\"num_attention_heads\":32,\"num_key_value_heads\":4,\"hidden_size\":2048}"}
}
override_data {
 target=data.http.fallback_tokenizer[0]
 values={status_code=200,response_body="{\"chat_template\":\"fixture\"}"}
}
run "GGUF_profiles_the_declared_BF16_config_without_claiming_resident_memory" {
 command=plan
 assert {
  condition=output.profile.model.repository=="RecursiveSI/flint-nvfp4-gguf" && output.profile.model.chat_template_available && output.profile.architecture.architectures[0]=="FlintForCausalLM" && output.profile.memory.status=="unsupported" && output.profile.weights.checkpoint_download_bytes==23000000000
  error_message="Preserve GGUF checkpoint identity, obtain declared config/tokenizer and keep resident-memory uncertainty."
 }
 assert {
  condition=strcontains(data.http.fallback_config[0].url,"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb") && output.profile.model.config_sources.revisions["RecursiveSI/flint"]=="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  error_message="Fallback metadata must be pinned independently of the GGUF weights."
 }
}
