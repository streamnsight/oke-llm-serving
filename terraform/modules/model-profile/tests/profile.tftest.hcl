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
