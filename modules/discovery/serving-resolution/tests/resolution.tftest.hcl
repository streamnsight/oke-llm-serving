# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "http" {}
override_data {
  target = data.http.recipe_metadata[0]
  values = { status_code = 404, response_body = "{}" }
}
variables {
  profile         = { model = { repository = "RecursiveSI/flint", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, architecture = { architectures = ["FlintForCausalLM"] } }
  recipe_features = ["reasoning"]
}
override_data {
  target = data.http.recipe_commit[0]
  values = { status_code = 200, response_body = "{\"sha\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"}" }
}
override_data {
  target = data.http.recipe[0]
  values = { status_code = 200, response_body = "meta:\n  default_hardware: gb200\n  hardware: {gb200: verified}\nmodel:\n  model_id: RecursiveSI/flint\n  min_vllm_version: nightly\n  base_args: []\n  base_env: {TEST_SETTING: 1}\nvariants:\n  default: {precision: bf16}\nfeatures:\n  reasoning: {args: [--reasoning-parser, glm47],env: {FEATURE_SETTING: enabled}}\ncompatible_strategies: [single_node_tp]\nstrategy_overrides:\n  single_node_tp: {tp: 1}\n" }
}
override_data {
  target = data.http.tags
  values = { status_code = 200, response_body = "[{\"name\":\"v0.34.0rc1\"},{\"name\":\"v0.33.0\"},{\"name\":\"v0.32.0\"}]" }
}
override_data {
  target = data.http.stable_commit[0]
  values = { status_code = 200, response_body = "{\"sha\":\"cccccccccccccccccccccccccccccccccccccccc\"}" }
}
override_data {
  target = data.http.stable_registry
  values = { status_code = 200, response_body = "\"FlintForCausalLM\": (\"vllm.models.flint\", \"FlintForCausalLM\")" }
}
override_data {
  target = data.http.nightly_commit
  values = { status_code = 200, response_body = "{\"sha\":\"dddddddddddddddddddddddddddddddddddddddd\"}" }
}
override_data {
  target = data.http.nightly_registry
  values = { status_code = 200, response_body = "\"FlintForCausalLM\": (\"vllm.models.flint\", \"FlintForCausalLM\")" }
}
override_data {
  target = data.http.image
  values = { status_code = 200, response_body = "{\"images\":[{\"os\":\"linux\",\"architecture\":\"amd64\",\"digest\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"}]}" }
}
run "stable_supersedes_old_nightly_hint" {
  command = plan
  assert {
    condition     = output.resolution.engine.version == "0.33.0" && output.resolution.status == "resolved_requires_validation" && strcontains(output.resolution.engine_selection_reason, "Recipe says nightly") && local.image_tag == "v0.33.0"
    error_message = "Stable source support must supersede a stale nightly hint without picking an rc tag."
  }
  assert {
    condition     = tolist(output.resolution.recipe.args) == tolist(["--reasoning-parser", "glm47"]) && output.resolution.recipe.env.TEST_SETTING == "1" && output.resolution.recipe.env.FEATURE_SETTING == "enabled" && strcontains(data.http.recipe[0].url, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    error_message = "Freeze source and explicitly selected feature argv/env without executing prose."
  }
}
run "explicit_nightly_is_allowed_and_pinned" {
  command = plan
  variables { engine_channel = "nightly" }
  assert {
    condition     = output.resolution.engine.version == "nightly" && strcontains(output.resolution.engine.image, "@sha256:") && output.resolution.engine.runtime_validation == "not_run"
    error_message = "Nightly must remain selectable and digest-pinned, without claiming validation."
  }
}
run "unknown_stable_architecture_falls_back_to_nightly" {
  command = plan
  override_data {
    target = data.http.stable_registry
    values = { status_code = 200, response_body = "\"LlamaForCausalLM\"" }
  }
  assert {
    condition     = output.resolution.engine.version == "nightly" && output.resolution.status == "resolved_requires_validation"
    error_message = "Auto mode must look up nightly when stable lacks the declared architecture."
  }
}
run "absent_recipe_keeps_engine_evidence_but_requires_expert" {
  command = plan
  variables {
    profile = { model = { repository = "custom/model", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, architecture = { architectures = ["FlintForCausalLM"] } }
  }
  override_data {
    target = data.http.recipe[0]
    values = { status_code = 404, response_body = "404: Not Found" }
  }
  assert {
    condition     = output.resolution.status == "requires_expert_configuration" && output.resolution.recipe.status == "requires_validation" && output.resolution.engine.image != null
    error_message = "Missing recipe must not erase a supporting engine or fabricate a serving configuration."
  }
}
run "missing_platform_digest_is_unresolved" {
  command = plan
  variables { engine_platform = "linux/arm64" }
  assert {
    condition     = output.resolution.engine.image == null && length(output.resolution.engine_issues) > 0
    error_message = "Never substitute an amd64 image for a missing arm64 image."
  }
}
run "managed_flags_need_expert_review" {
  command = plan
  override_data {
    target = data.http.recipe[0]
    values = { status_code = 200, response_body = "meta: {default_hardware: gb200}\nmodel: {model_id: RecursiveSI/flint, base_args: [--tensor-parallel-size, '8']}\nvariants: {default: {precision: bf16}}\n" }
  }
  variables { recipe_features = [] }
  assert {
    condition     = output.resolution.status == "requires_expert_configuration" && anytrue([for r in output.resolution.recipe.issues : strcontains(r, "managed settings")])
    error_message = "Recipe flags cannot silently conflict with controlled deployment topology."
  }
}

run "blank_optional_version_uses_auto_selection" {
  command = plan
  variables { engine_version = "" }
  assert {
    condition     = output.resolution.engine.version == "0.33.0"
    error_message = "An empty RMS optional version field must behave like no override."
  }
}

run "feature_modes_are_not_silently_ignored" {
  command = plan
  override_data {
    target = data.http.recipe[0]
    values = { status_code = 200, response_body = "meta: {default_hardware: gb200}\nmodel: {model_id: RecursiveSI/flint}\nvariants: {default: {precision: bf16}}\nfeatures:\n  reasoning: {modes: {enabled: {args: [--reasoning-parser, glm47]}}}\n" }
  }
  assert {
    condition     = output.resolution.status == "requires_expert_configuration" && anytrue([for r in output.resolution.recipe.issues : strcontains(r, "mode or companion")])
    error_message = "Complex feature mode semantics must require expert interpretation rather than dropping flags silently."
  }
}
run "live_metadata_supplies_the_recipe_owner_and_path" {
  command = plan
  variables { recipe_features = [] }
  override_data {
    target = data.http.recipe_metadata[0]
    values = { status_code = 200, response_body = "{\"source\":{\"repo\":\"vllm-project/recipes\",\"sha\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"path\":\"models/RecursiveSI/flint.yaml\"}}" }
  }
  assert {
    condition     = output.resolution.recipe.status == "resolved" && strcontains(output.resolution.recipe.source_url, "vllm-project/recipes/") && strcontains(output.resolution.recipe.source_url, "models/RecursiveSI/flint.yaml")
    error_message = "Resolve the live recipe owner/path, without a static alias catalog or legacy source fallback."
  }
}
run "discovery_assesses_nightly_without_requiring_a_user_choice" {
  command = plan
  variables {
    assess_alternatives = true
    recipe_features     = []
  }
  override_data {
    target = data.http.alternative_image
    values = { status_code = 200, response_body = "{\"images\":[{\"os\":\"linux\",\"architecture\":\"amd64\",\"digest\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"}]}" }
  }
  assert {
    condition     = length(output.resolution.engine_candidates) == 2 && output.resolution.engine_candidates[1].channel == "nightly" && length(output.resolution.recipe.args) == 0 && contains(keys(output.resolution.recipe.feature_options), "reasoning")
    error_message = "Discovery should assess image/feature alternatives, leaving feature activation to deployment."
  }
}

run "shared_recipe_snapshot_avoids_duplicate_metadata_and_commit_reads" {
  command = plan
  variables {
    recipe_features = []
    recipe_metadata = {
      url  = "https://recipes.vllm.ai/RecursiveSI/flint.json", status_code = 200,
      body = { source = { repo = "vllm-project/recipes", sha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", path = "models/RecursiveSI/flint.yaml" } }
    }
  }
  assert {
    condition     = length(data.http.recipe_metadata) == 0 && length(data.http.recipe_commit) == 0 && strcontains(data.http.recipe[0].url, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    error_message = "A shared immutable recipe snapshot must eliminate repeated metadata/SHA-resolution requests."
  }
}
run "absent_shared_recipe_avoids_useless_source_lookups" {
  command = plan
  variables { recipe_metadata = { url = "https://recipes.vllm.ai/org/absent.json", status_code = 404, body = {} } }
  assert {
    condition     = length(data.http.recipe_metadata) == 0 && length(data.http.recipe_commit) == 0 && length(data.http.recipe) == 0 && output.resolution.recipe.status == "requires_validation"
    error_message = "An absent shared recipe must preserve engine assessment without probing guessed recipe GitHub paths."
  }
}
run "stable_tag_commit_is_reused_without_a_second_resolution_call" {
  command = plan
  override_data {
    target = data.http.tags
    values = { status_code = 200, response_body = "[{\"name\":\"v0.33.0\",\"commit\":{\"sha\":\"cccccccccccccccccccccccccccccccccccccccc\"}}]" }
  }
  assert {
    condition     = length(data.http.stable_commit) == 0 && strcontains(data.http.stable_registry.url, "cccccccccccccccccccccccccccccccccccccccc") && output.resolution.engine.source_commit == "cccccccccccccccccccccccccccccccccccccccc"
    error_message = "The exact immutable SHA already returned by tag enumeration must be reused."
  }
}
run "all_recommended_and_alternative_images_are_registry_qualified" {
  command = plan
  variables {
    assess_alternatives = true
    recipe_features     = []
  }
  override_data {
    target = data.http.image
    values = { status_code = 200, response_body = "{\"images\":[{\"os\":\"linux\",\"architecture\":\"amd64\",\"digest\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"},{\"os\":\"linux\",\"architecture\":\"arm64\",\"digest\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]}" }
  }
  override_data {
    target = data.http.alternative_image
    values = { status_code = 200, response_body = "{\"images\":[{\"os\":\"linux\",\"architecture\":\"amd64\",\"digest\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"},{\"os\":\"linux\",\"architecture\":\"arm64\",\"digest\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"}]}" }
  }
  assert {
    condition     = output.resolution.engine.image == "docker.io/vllm/vllm-openai@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" && output.resolution.engine_candidates[1].image == "docker.io/vllm/vllm-openai@sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" && alltrue([for image in flatten(concat([[output.resolution.engine.image], values(output.resolution.engine.available_images)], [for engine in output.resolution.engine_candidates : concat([engine.image], values(engine.available_images))])) : can(regex("^docker[.]io/vllm/vllm-openai@sha256:[a-f0-9]{64}$", image))]) && length(output.resolution.engine.available_images) == 2 && length(output.resolution.engine_candidates[1].available_images) == 2
    error_message = "Every stable/nightly image and architecture alternative must retain its digest and explicit registry, so runtimes never resolve an ambiguous short name."
  }
  assert {
    condition     = output.resolution.engine.version == "0.33.0" && output.resolution.engine.image_metadata_url == "https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags/v0.33.0" && output.resolution.engine_candidates[1].image_metadata_url == "https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags/nightly"
    error_message = "Qualifying image names must not alter source engine versions or Docker Hub metadata HTTP repository paths."
  }
}
