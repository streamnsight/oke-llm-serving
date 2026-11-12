# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "http" {}
variables {
  image = "vllm/vllm-openai@sha256:ffdd332f0605be6d8caa0f7c6dbff9295ee2612ae0a8d4fb13537b6de861aeab"
}
override_data {
  target = data.http.token[0]
  values = { status_code = 200, response_body = "{\"token\":\"public-test-token\"}" }
}
override_data {
  target = data.http.manifest[0]
  values = { status_code = 200, response_body = "{\"config\":{\"digest\":\"sha256:ee62f66c5d0f39afe68d829df35dfd3b888cc6d7b67e29e22d26d9fe8995667c\"}}" }
}
override_data {
  target = data.http.config[0]
  values = { status_code = 200, response_body = "{\"config\":{\"Env\":[\"CUDA_VERSION=13.2.0\",\"NVIDIA_REQUIRE_CUDA=cuda>=13.2\",\"OTHER=not-exported\"]}}\n" }
}
run "extract_cuda_from_verified_container_configuration" {
  command = plan
  assert {
    condition     = output.runtime.cuda_version == "13.2.0" && output.runtime.minor_compatibility_driver_floor == "580" && output.runtime.nvidia_require_cuda == "cuda>=13.2" && output.runtime.status != "validated"
    error_message = "Report the container's actual metadata and baseline without claiming node/driver/kernel compatibility."
  }
}
run "reject_configuration_digest_mismatch" {
  command = plan
  override_data {
    target = data.http.config[0]
    values = { status_code = 200, response_body = "{}" }
  }
  expect_failures = [data.http.config]
}
run "custom_registry_is_explicitly_unknown" {
  command = plan
  variables { image = "private.example/engine@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  assert {
    condition     = length(data.http.token) == 0 && output.runtime.cuda_version == null && output.runtime.status == "unknown_requires_runtime_validation"
    error_message = "Do not guess CUDA metadata or attempt anonymous credentials against arbitrary private registries."
  }
}
