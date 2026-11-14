# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# One snapshot is shared by profiling, engine resolution and hardware planning.
# It depends only on the requested repository, avoiding a profile/recipe cycle.
data "http" "model_recipe" {
  url                = "https://recipes.vllm.ai/${trimsuffix(trimprefix(trimspace(var.model), "https://huggingface.co/"), "/")}.json"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition = self.status_code == 404 || try(
        self.status_code == 200 &&
        can(regex("^vllm-project/[A-Za-z0-9_.-]+$", jsondecode(self.response_body).source.repo)) &&
        can(regex("^[a-f0-9]{40}$", jsondecode(self.response_body).source.sha)) &&
        can(regex("^(recipes/)?models/", jsondecode(self.response_body).source.path)), false
      )
      error_message = "Recipe metadata failed or lacks a valid immutable upstream source identity; only HTTP 404 means absent."
    }
  }
}
locals {
  recipe_metadata_snapshot = {
    url         = data.http.model_recipe.url
    status_code = data.http.model_recipe.status_code
    body        = try(jsondecode(data.http.model_recipe.response_body), {})
  }
}
