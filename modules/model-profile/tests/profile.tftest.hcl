# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "http" {}

variables {
  model          = "https://huggingface.co/org/model"
  context_length = 100
  concurrency    = 2
  runtime_gib    = 0
  margin         = 0
}

override_data {
  target = data.http.model
  values = {
    status_code   = 200
    response_body = "{\"sha\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"safetensors\":{\"parameters\":{\"BF16\":6},\"total\":6},\"siblings\":[{\"rfilename\":\"model.safetensors\"}]}"
  }
}
override_data {
  target = data.http.config
  values = {
    status_code   = 200
    response_body = "{\"model_type\":\"llama\",\"num_hidden_layers\":2,\"num_attention_heads\":4,\"num_key_value_heads\":2,\"hidden_size\":16,\"max_position_embeddings\":4096}"
  }
}

run "dense_native_estimate" {
  command = plan
  assert {
    condition     = output.profile.memory.status == "estimated" && output.profile.memory.weight_bytes == 12 && output.profile.memory.kv_bytes_per_token == 64 && output.profile.memory.kv_bytes == 12800 && output.profile.memory.recommended_aggregate_bytes == 12812
    error_message = "Native HCL must compute weights and full-context GQA KV correctly."
  }
  assert {
    condition     = data.http.config.url == "https://huggingface.co/org/model/resolve/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/config.json" && output.profile.weights.confidence == "declared_metadata"
    error_message = "Config must be SHA-pinned and Hub counts must not be called independently measured."
  }
}

run "moe_counts_all_experts" {
  command = plan
  override_data {
    target = data.http.config
    values = {
      status_code   = 200
      response_body = "{\"model_type\":\"mixtral\",\"num_hidden_layers\":2,\"num_attention_heads\":4,\"num_key_value_heads\":2,\"hidden_size\":16,\"num_local_experts\":8,\"num_experts_per_tok\":2}"
    }
  }
  assert {
    condition     = output.profile.architecture.kind == "moe" && output.profile.memory.weight_bytes == 12
    error_message = "Active experts must not reduce total resident weight memory."
  }
}

run "context_over_maximum" {
  command = plan
  variables { context_length = 8192 }
  assert {
    condition     = output.profile.memory.status == "unsupported" && output.profile.memory.recommended_aggregate_bytes == null
    error_message = "Context extension must not be assumed."
  }
}

run "missing_counts" {
  command = plan
  override_data {
    target = data.http.model
    values = {
      status_code   = 200
      response_body = "{\"sha\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"siblings\":[{\"rfilename\":\"model.safetensors\"}]}"
    }
  }
  assert {
    condition     = output.profile.memory.status == "unsupported" && output.profile.memory.recommended_aggregate_bytes == null
    error_message = "Missing Hub metadata must not fabricate a memory estimate."
  }
}

run "unknown_dtype" {
  command = plan
  override_data {
    target = data.http.model
    values = {
      status_code   = 200
      response_body = "{\"sha\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"safetensors\":{\"parameters\":{\"I32\":6},\"total\":6},\"siblings\":[{\"rfilename\":\"model.safetensors\"}]}"
    }
  }
  assert {
    condition     = output.profile.memory.status == "unsupported" && output.profile.weights.tensor_data_bytes == null
    error_message = "Packed/integer tensor types require dedicated estimators."
  }
}

run "reject_invalid_assumptions" {
  command = plan
  variables { concurrency = 0 }
  expect_failures = [var.concurrency]
}

override_data {
  target = data.http.card
  values = { status_code = 404, response_body = "" }
}

run "extract_card_version_evidence" {
  command = plan
  override_data {
    target = data.http.card
    values = { status_code = 200, response_body = "Use vllm>=0.8.5 or sglang>=0.4.6.post1.\nNo minimum is implied by a bare framework name." }
  }
  assert {
    condition     = output.profile.serving_requirements.status == "version_hints_found" && length(output.profile.serving_requirements.version_hints) == 2 && output.profile.serving_requirements.version_hints[0].operator == ">=" && output.profile.serving_requirements.version_hints[1].version == "0.4.6.post1"
    error_message = "Version extraction must preserve explicit expressions and evidence without inventing minimum versions."
  }
}
run "float32_resident_conversion_is_reserved" {
  command = plan
  variables { kv_dtype = "float32" }
  assert {
    condition     = output.profile.weights.tensor_data_bytes == 12 && output.profile.memory.weight_bytes == 24 && output.profile.memory.kv_bytes == 25600
    error_message = "Serving float32 must reserve converted weights and KV, without altering measured checkpoint byte metadata."
  }
}
run "storage_bytes_do_not_fabricate_quantized_GPU_memory" {
  command=plan
  override_data {
    target=data.http.model
    values={status_code=200,response_body="{\"sha\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"siblings\":[{\"rfilename\":\"model-00000.safetensors\",\"size\":1000},{\"rfilename\":\"model-00001.safetensors\",\"size\":2000}]}"}
  }
  assert {
    condition=output.profile.weights.checkpoint_download_bytes==3000 && output.profile.memory.status=="unsupported" && output.profile.weights.tensor_data_bytes==null
    error_message="File sizes can size checkpoint storage but cannot become a quantized resident-memory estimate."
  }
}
