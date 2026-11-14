# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_providers { http = { source = "hashicorp/http", version = "~> 3.4" } }
}
variable "image" { type = string }
locals {
  reference = try(regex("^(?:docker.io/)?(?P<repository>vllm/vllm-openai)@(?P<digest>sha256:[a-f0-9]{64})$", var.image), null)
}
data "http" "token" {
  count              = local.reference == null ? 0 : 1
  url                = "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${local.reference.repository}:pull"
  request_timeout_ms = 30000
}
data "http" "manifest" {
  count              = local.reference == null ? 0 : 1
  url                = "https://registry-1.docker.io/v2/${local.reference.repository}/manifests/${local.reference.digest}"
  request_timeout_ms = 30000
  request_headers    = { Authorization = "Bearer ${jsondecode(data.http.token[0].response_body).token}", Accept = "application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json" }
  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && "sha256:${sha256(self.response_body)}" == local.reference.digest
      error_message = "Serving image manifest must match the frozen platform digest."
    }
  }
}
locals { config_digest = try(jsondecode(data.http.manifest[0].response_body).config.digest, null) }
data "http" "config" {
  count              = local.reference == null ? 0 : 1
  url                = "https://registry-1.docker.io/v2/${local.reference.repository}/blobs/${local.config_digest}"
  request_timeout_ms = 30000
  request_headers    = { Authorization = "Bearer ${jsondecode(data.http.token[0].response_body).token}" }
  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && "sha256:${sha256(self.response_body)}" == local.config_digest
      error_message = "Serving image configuration must match its manifest's content digest."
    }
  }
}
locals {
  env        = { for entry in try(jsondecode(data.http.config[0].response_body).config.Env, []) : split("=", entry)[0] => join("=", slice(split("=", entry), 1, length(split("=", entry)))) }
  cuda       = lookup(local.env, "CUDA_VERSION", null)
  cuda_major = try(tonumber(split(".", local.cuda)[0]), 0)
}
output "runtime" {
  value = {
    image                            = var.image, cuda_version = local.cuda,
    nvidia_require_cuda              = lookup(local.env, "NVIDIA_REQUIRE_CUDA", null),
    minor_compatibility_driver_floor = lookup({ "11" = "450.80.02", "12" = "525", "13" = "580" }, tostring(local.cuda_major), null),
    status                           = local.cuda == null ? "unknown_requires_runtime_validation" : "container_metadata_only_driver_and_kernels_require_runtime_validation",
    source                           = local.reference == null ? null : "digest_verified_public_image_config",
    driver_reference                 = "https://docs.nvidia.com/deploy/cuda-compatibility/minor-version-compatibility.html"
  }
}
