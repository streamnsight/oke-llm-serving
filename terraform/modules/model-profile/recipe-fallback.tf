# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Some GGUF variants intentionally omit config/tokenizer; follow only the recipe's
# explicit structured references, pinning their Hub revisions independently.
locals {
  fallback_recipe = try([for m in jsondecode(file("${path.module}/../../../catalogs/models.json")).models : m.recipes[0].recipe_model_id if m.id == local.repository][0], null)
}
data "http" "fallback_recipe" {
  count              = data.http.config.status_code == 404 && local.fallback_recipe != null ? 1 : 0
  url                = "https://recipes.vllm.ai/${local.fallback_recipe}.json"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Model has no config.json and its declared recipe could not be retrieved."
    }
  }
}
locals {
  fallback_metadata     = try(jsondecode(data.http.fallback_recipe[0].response_body), {})
  fallback_variants     = [for v in try(local.fallback_metadata.variants, {}) : v if try(v.model_id, "") == local.repository]
  fallback_args         = try(one(local.fallback_variants).extra_args, [])
  config_repository     = try(local.fallback_args[index(local.fallback_args, "--hf-config-path") + 1], null)
  tokenizer_repository  = try(local.fallback_args[index(local.fallback_args, "--tokenizer") + 1], local.config_repository)
  fallback_repositories = toset(compact([local.config_repository, local.tokenizer_repository]))
}
data "http" "fallback_model" {
  for_each           = local.fallback_repositories
  url                = "https://huggingface.co/api/models/${each.key}/revision/main"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && can(regex("^[a-f0-9]{40}$", jsondecode(self.response_body).sha))
      error_message = "Could not pin the recipe's config/tokenizer repository."
    }
  }
}
data "http" "fallback_config" {
  count              = local.config_repository != null ? 1 : 0
  url                = "https://huggingface.co/${local.config_repository}/resolve/${jsondecode(data.http.fallback_model[local.config_repository].response_body).sha}/config.json"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && can(keys(jsondecode(self.response_body)))
      error_message = "Recipe config fallback could not be read."
    }
  }
}
data "http" "fallback_tokenizer" {
  count              = local.tokenizer_repository != null ? 1 : 0
  url                = "https://huggingface.co/${local.tokenizer_repository}/resolve/${jsondecode(data.http.fallback_model[local.tokenizer_repository].response_body).sha}/tokenizer_config.json"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Recipe tokenizer fallback could not be read."
    }
  }
}
