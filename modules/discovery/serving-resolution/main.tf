# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { http = { source = "hashicorp/http", version = "~> 3.4" } }
}
locals {
  version_override = try(length(trimspace(var.engine_version)) > 0, false) ? trimspace(var.engine_version) : null
  model            = var.profile.model.repository
  arches           = try(var.profile.architecture.architectures, [])
  metadata         = jsondecode(var.recipe_metadata != null ? jsonencode(var.recipe_metadata.body) : try(data.http.recipe_metadata[0].response_body, "{}"))
  repository       = try(local.metadata.source.repo, "vllm-project/vllm")
  source_ref       = try(local.metadata.source.sha, "main")
  path             = try(local.metadata.source.path, "recipes/models/${local.model}.yaml")
}
data "http" "recipe_metadata" {
  count              = var.recipe_metadata == null ? 1 : 0
  url                = "https://recipes.vllm.ai/${local.model}.json"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = self.status_code == 404 || try(self.status_code == 200 && can(regex("^vllm-project/[A-Za-z0-9_.-]+$", jsondecode(self.response_body).source.repo)) && can(regex("^[a-f0-9]{40}$", jsondecode(self.response_body).source.sha)) && can(regex("^(recipes/)?models/", jsondecode(self.response_body).source.path)), false)
      error_message = "Recipe metadata lookup failed or did not supply a valid upstream source identity."
    }
  }
}
data "http" "recipe_commit" {
  count              = var.recipe_metadata == null ? 1 : 0
  url                = "https://api.github.com/repos/${local.repository}/commits/${local.source_ref}"
  request_headers    = { Accept = "application/vnd.github+json" }
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && can(regex("^[a-f0-9]{40}$", jsondecode(self.response_body).sha))
      error_message = "Could not resolve the recipe source commit; API/access failures are not absent recipes."
    }
  }
}
data "http" "recipe" {
  count              = var.recipe_metadata == null ? 1 : var.recipe_metadata.status_code == 200 ? 1 : 0
  url                = "https://raw.githubusercontent.com/${local.repository}/${coalesce(local.recipe_sha, "unresolved")}/${local.path}"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = contains([200, 404], self.status_code)
      error_message = "Recipe request failed; only HTTP 404 means absent."
    }
  }
}
locals {
  recipe_status = try(data.http.recipe[0].status_code, 404)
  recipe_body   = try(data.http.recipe[0].response_body, "{}")
  recipe_url    = try(data.http.recipe[0].url, var.recipe_metadata.url, null)
  recipe_sha    = var.recipe_metadata != null ? try(local.metadata.source.sha, null) : jsondecode(data.http.recipe_commit[0].response_body).sha
}
locals {
  recipe            = try(yamldecode(local.recipe_body), {})
  variants          = try(local.recipe.variants, {})
  variant_matches   = [for name, v in local.variants : name if try(v.model_id, local.recipe.model.model_id) == local.model]
  variant_name      = contains(local.variant_matches, "default") ? "default" : try(one(local.variant_matches), null)
  variant           = try(local.variants[local.variant_name], {})
  hardware          = try(local.recipe.meta.default_hardware, "undetermined")
  hardware_override = try(local.recipe.hardware_overrides[local.hardware], {})
  variant_hardware  = try(local.variant.hardware_overrides[local.hardware], {})
  feature_args      = flatten([for name in sort(tolist(var.recipe_features)) : try(local.recipe.features[name].hardware_overrides[local.hardware].args, local.recipe.features[name].args, [])])
  feature_env       = merge({}, [for name in sort(tolist(var.recipe_features)) : merge(try(local.recipe.features[name].env, {}), try(local.recipe.features[name].hardware_overrides[local.hardware].env, {}))]...)
  args              = concat(try(local.variant.base_args, local.recipe.model.base_args, []), try(local.variant.extra_args, []), try(local.hardware_override.extra_args, []), try(local.variant_hardware.extra_args, []), local.feature_args)
  env               = { for k, v in merge(try(local.recipe.model.base_env, {}), try(local.variant.extra_env, {}), try(local.hardware_override.extra_env, {}), try(local.variant_hardware.extra_env, {}), local.feature_env) : k => tostring(v) }
  # Managed identity/topology/memory flags must come from deployment variables, not recipe args.
  managed_flags = ["--model", "--revision", "--served-model-name", "--host", "--port", "--tensor-parallel-size", "-tp", "--pipeline-parallel-size", "-pp", "--max-model-len", "--max-num-seqs", "--dtype", "--kv-cache-dtype", "--gpu-memory-utilization", "--distributed-executor-backend", "--nnodes", "--node-rank", "--master-addr", "--headless"]
  recipe_issues = compact([
    local.recipe_status == 200 && can(local.recipe.model.model_id) ? "" : "No parseable structured vLLM recipe was found.",
    local.variant_name != null ? "" : "Recipe does not identify one variant matching the requested checkpoint.",
    alltrue([for f in var.recipe_features : contains(keys(try(local.recipe.features, {})), f)]) ? "" : "Requested recipe feature is not declared.",
    alltrue([for f in var.recipe_features : try(contains(local.variant.supported_features, f), true)]) ? "" : "Selected variant does not support a requested feature.",
    anytrue([for f in var.recipe_features : try(length(local.recipe.features[f].modes) > 0, false) || try(local.recipe.features[f].companion != null, false)]) ? "Selected feature needs mode or companion configuration; supply expert settings." : "",
    anytrue([for f in var.recipe_features : try(local.recipe.features[f].hardware[local.hardware] == "unsupported", false)]) ? "Selected feature is unsupported on the recipe's selected hardware." : "",
    try(length(local.recipe.dependencies) > 0, false) ? "Recipe dependencies need expert deployment configuration." : "",
    alltrue([for a in local.args : can(tostring(a)) && !strcontains(a, "$${")]) ? "" : "Recipe arguments contain unresolved templates.",
    anytrue([for a in local.args : contains(local.managed_flags, split("=", a)[0])]) ? "Recipe arguments override managed settings; expert review is required." : "",
    try(local.variant.docker_image, null) == null ? "" : "Variant requires a custom image; the generic vLLM image cannot be assumed equivalent.",
    try(local.recipe.model.docker_image, null) == null ? "" : "Recipe requires a custom image.",
  ])
  recipe_valid     = length(local.recipe_issues) == 0
  minimum          = try(local.variant.min_vllm_version, local.recipe.model.min_vllm_version, "unspecified")
  nightly_required = try(local.variant.nightly_required, false)
}
# Do not trust /releases/latest to be a stable tag: upstream can point it at an rc.
data "http" "tags" {
  url                = "https://api.github.com/repos/vllm-project/vllm/tags?per_page=100"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && can(tolist(jsondecode(self.response_body)))
      error_message = "Unable to enumerate vLLM tags. Supply an explicit version after resolving the API failure."
    }
  }
}
locals {
  stable_tags    = { for t in jsondecode(data.http.tags.response_body) : join(".", [for n in split(".", trimprefix(t.name, "v")) : format("%08d", tonumber(n))]) => t if can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", t.name)) }
  latest_tag     = try(local.stable_tags[reverse(sort(keys(local.stable_tags)))[0]].name, "unresolved")
  stable_tag     = local.version_override != null ? "v${local.version_override}" : local.latest_tag
  tag_source_sha = try(one([for tag in values(local.stable_tags) : tag.commit.sha if tag.name == local.stable_tag && can(regex("^[a-f0-9]{40}$", tag.commit.sha))]), null)
}
data "http" "stable_commit" {
  count              = local.tag_source_sha == null ? 1 : 0
  url                = "https://api.github.com/repos/vllm-project/vllm/commits/${local.stable_tag}"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = contains([200, 404], self.status_code)
      error_message = "Stable source lookup failed."
    }
  }
}
locals {
  stable_source_sha = coalesce(local.tag_source_sha, try(jsondecode(data.http.stable_commit[0].response_body).sha, null), "unresolved")
}
data "http" "stable_registry" {
  url                = "https://raw.githubusercontent.com/vllm-project/vllm/${local.stable_source_sha}/vllm/model_executor/models/registry.py"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = contains([200, 404], self.status_code)
      error_message = "Stable architecture registry lookup failed."
    }
  }
}
locals {
  stable_support  = data.http.stable_registry.status_code == 200 && anytrue([for a in local.arches : strcontains(data.http.stable_registry.response_body, "\"${a}\"")])
  numeric_minimum = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", local.minimum))
  minimum_met     = !local.numeric_minimum ? true : try(sum([for i, n in split(".", trimprefix(local.stable_tag, "v")) : tonumber(n) * pow(1000000, 2 - i)]) >= sum([for i, n in split(".", trimprefix(local.minimum, "v")) : tonumber(n) * pow(1000000, 2 - i)]), false)
  use_nightly     = var.engine_channel == "nightly" || (var.engine_channel == "auto" && local.version_override == null && (!local.stable_support || !local.minimum_met || local.nightly_required))
}
data "http" "nightly_commit" {
  count              = local.use_nightly || var.assess_alternatives ? 1 : 0
  url                = "https://api.github.com/repos/vllm-project/vllm/commits/main"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && can(regex("^[a-f0-9]{40}$", jsondecode(self.response_body).sha))
      error_message = "Nightly source lookup failed."
    }
  }
}
data "http" "nightly_registry" {
  count              = local.use_nightly || var.assess_alternatives ? 1 : 0
  url                = "https://raw.githubusercontent.com/vllm-project/vllm/${jsondecode(data.http.nightly_commit[0].response_body).sha}/vllm/model_executor/models/registry.py"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Nightly architecture registry lookup failed."
    }
  }
}
locals {
  image_tag        = local.use_nightly ? "nightly" : local.stable_tag
  registry_body    = local.use_nightly ? data.http.nightly_registry[0].response_body : data.http.stable_registry.response_body
  supported_arches = [for a in local.arches : a if strcontains(local.registry_body, "\"${a}\"")]
  source_sha       = try(local.use_nightly ? jsondecode(data.http.nightly_commit[0].response_body).sha : local.stable_source_sha, null)
}
data "http" "image" {
  url                = "https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags/${local.image_tag}"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = contains([200, 404], self.status_code)
      error_message = "Image lookup failed; only 404 means the image tag is absent."
    }
  }
}
locals {
  image_metadata = try(jsondecode(data.http.image.response_body), {})
  image_digest   = try(one([for i in local.image_metadata.images : i.digest if "${i.os}/${i.architecture}" == var.engine_platform]), null)
  image_pinned   = can(regex("^sha256:[a-f0-9]{64}$", local.image_digest))
  engine_issues = compact([
    length(local.supported_arches) > 0 ? "" : "Selected engine source does not declare the model architecture.",
    local.image_pinned ? "" : "No immutable image digest was found for the requested platform.",
    local.use_nightly || local.minimum_met ? "" : "Stable engine is older than the recipe minimum.",
    !local.nightly_required || local.use_nightly ? "" : "Variant explicitly requires nightly; stable selection needs expert review.",
    local.minimum == "nightly" || local.minimum == "unspecified" || local.numeric_minimum ? "" : "Recipe version requirement needs expert interpretation.",
    local.version_override == null || var.engine_channel != "nightly" ? "" : "Do not combine a stable version override with the nightly channel.",
  ])
  engine_valid = length(local.engine_issues) == 0
  engine = {
    id                       = "vllm-${local.image_tag}-${replace(var.engine_platform, "/", "-")}", framework = "vllm", version = local.use_nightly ? "nightly" : trimprefix(local.stable_tag, "v")
    image                    = local.image_pinned ? "docker.io/vllm/vllm-openai@${local.image_digest}" : null
    platform                 = var.engine_platform, architectures = local.supported_arches
    gpu_compute_capabilities = distinct([for gpu in values(jsondecode(file("${path.module}/../accelerator-inventory/data/gpus.json")).shapes) : gpu.compute_capability if try(gpu.compute_capability >= (try(var.profile.memory.assumptions.kv_dtype, "bfloat16") == "bfloat16" ? 80 : 75), false)])
    source                   = "https://github.com/vllm-project/vllm/blob/${coalesce(local.source_sha, "unresolved")}/vllm/model_executor/models/registry.py"
    source_commit            = local.source_sha, image_tag = local.image_tag, image_metadata_url = data.http.image.url
    image_source_association = "upstream_tag_metadata_not_independently_verified", runtime_validation = "not_run", driver_validation = "required", multi_node_backend = "mp"
  }
}
data "http" "alternative_image" {
  count              = var.assess_alternatives && !local.use_nightly ? 1 : 0
  url                = "https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags/nightly"
  request_timeout_ms = 60000
  lifecycle {
    postcondition {
      condition     = contains([200, 404], self.status_code)
      error_message = "Nightly alternative image lookup failed."
    }
  }
}
locals {
  available_images   = { for i in try(local.image_metadata.images, []) : "${i.os}/${i.architecture}" => "docker.io/vllm/vllm-openai@${i.digest}" if i.os == "linux" && contains(["amd64", "arm64"], i.architecture) && can(regex("^sha256:[a-f0-9]{64}$", i.digest)) }
  recommended_engine = merge(local.engine, { channel = local.use_nightly ? "nightly" : "stable", available_images = local.available_images })
  alternative_images = { for i in try(jsondecode(data.http.alternative_image[0].response_body).images, []) : "${i.os}/${i.architecture}" => "docker.io/vllm/vllm-openai@${i.digest}" if i.os == "linux" && contains(["amd64", "arm64"], i.architecture) && can(regex("^sha256:[a-f0-9]{64}$", i.digest)) }
  alternative_arches = [for a in local.arches : a if try(strcontains(data.http.nightly_registry[0].response_body, "\"${a}\""), false)]
  engine_candidates = concat([local.recommended_engine], [for include in [true] : merge(local.engine, {
    id                 = "vllm-nightly", version = "nightly", channel = "nightly", image_tag = "nightly", available_images = local.alternative_images,
    image              = lookup(local.alternative_images, var.engine_platform, null), architectures = local.alternative_arches,
    image_metadata_url = data.http.alternative_image[0].url,
    source_commit      = try(jsondecode(data.http.nightly_commit[0].response_body).sha, null),
    source             = "https://github.com/vllm-project/vllm/blob/${try(jsondecode(data.http.nightly_commit[0].response_body).sha, "unresolved")}/vllm/model_executor/models/registry.py"
  }) if var.assess_alternatives && !local.use_nightly && length(local.alternative_images) > 0 && length(local.alternative_arches) > 0])
}
output "resolution" {
  value = {
    schema_version = "1.0", model = var.profile.model, status = local.engine_valid && local.recipe_valid ? "resolved_requires_validation" : "requires_expert_configuration"
    recipe = { status = local.recipe_valid ? "resolved" : "requires_validation", source_url = local.recipe_url, source_commit = local.recipe_sha, sha256 = sha256(local.recipe_body), variant = local.variant_name, minimum_engine_version = local.minimum,
      hardware           = try(local.recipe.meta.hardware, {}), selected_hardware = local.hardware, compatible_strategies = try(local.recipe.compatible_strategies, []), strategy_overrides = try(local.recipe.strategy_overrides, {}),
      available_features = keys(try(local.recipe.features, {})), selected_features = sort(tolist(var.recipe_features)), args = local.args, env = local.env, issues = local.recipe_issues, feature_options = try(local.recipe.features, {}),
    variant_metadata = local.variant, install_requirements = try(local.recipe.model.install, {}) }
    deployment_profile      = try(local.recipe.deployment_profile, local.metadata.deployment_profile, {})
    engine                  = local.recommended_engine, engine_candidates = local.engine_candidates, engine_issues = local.engine_issues
    engine_selection_reason = local.use_nightly ? "Nightly requested or stable architecture/minimum coverage missing; digest frozen, runtime validation pending." : local.minimum == "nightly" ? "Recipe says nightly, but a stable tag declares the architecture; prefer stable, validate recipe flags at runtime." : "Latest or explicitly selected stable tag meets source architecture/minimum checks."
    warnings                = ["Source registration is evidence, not an image/GPU runtime test.", "Recipe hardware/strategy evidence does not establish compatibility for other GPUs.", "Image digest pins the selected platform; confirm the target OKE image/node CPU architecture."]
  }
}
