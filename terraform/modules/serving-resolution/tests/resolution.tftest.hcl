# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "http" {}
override_data {
 target=data.http.recipe_metadata
 values={status_code=404,response_body="{}"}
}
variables {
  profile         = { model = { repository = "RecursiveSI/flint", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, architecture = { architectures = ["FlintForCausalLM"] } }
  recipe_features = ["reasoning"]
}
override_data {
  target = data.http.recipe_commit
  values = { status_code = 200, response_body = "{\"sha\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"}" }
}
override_data {
  target = data.http.recipe
  values = { status_code = 200, response_body = "meta:\n  default_hardware: gb200\n  hardware: {gb200: verified}\nmodel:\n  model_id: RecursiveSI/flint\n  min_vllm_version: nightly\n  base_args: []\n  base_env: {TEST_SETTING: 1}\nvariants:\n  default: {precision: bf16}\nfeatures:\n  reasoning: {args: [--reasoning-parser, glm47],env: {FEATURE_SETTING: enabled}}\ncompatible_strategies: [single_node_tp]\nstrategy_overrides:\n  single_node_tp: {tp: 1}\n" }
}
override_data {
  target = data.http.tags
  values = { status_code = 200, response_body = "[{\"name\":\"v0.34.0rc1\"},{\"name\":\"v0.33.0\"},{\"name\":\"v0.32.0\"}]" }
}
override_data {
  target = data.http.stable_commit
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
    condition     = tolist(output.resolution.recipe.args) == tolist(["--reasoning-parser", "glm47"]) && output.resolution.recipe.env.TEST_SETTING == "1" && output.resolution.recipe.env.FEATURE_SETTING == "enabled" && strcontains(data.http.recipe.url, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
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
    target = data.http.recipe
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
    target = data.http.recipe
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
    target = data.http.recipe
    values = { status_code = 200, response_body = "meta: {default_hardware: gb200}\nmodel: {model_id: RecursiveSI/flint}\nvariants: {default: {precision: bf16}}\nfeatures:\n  reasoning: {modes: {enabled: {args: [--reasoning-parser, glm47]}}}\n" }
  }
  assert {
    condition     = output.resolution.status == "requires_expert_configuration" && anytrue([for r in output.resolution.recipe.issues : strcontains(r, "mode or companion")])
    error_message = "Complex feature mode semantics must require expert interpretation rather than dropping flags silently."
  }
}
run "live_metadata_supplies_the_recipe_owner_and_path" {
 command=plan
 variables {recipe_features=[]}
 override_data {
  target=data.http.recipe_metadata
  values={status_code=200,response_body="{\"source\":{\"repo\":\"vllm-project/recipes\",\"sha\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"path\":\"models/RecursiveSI/flint.yaml\"}}"}
 }
 assert {
  condition=output.resolution.recipe.status=="resolved" && strcontains(output.resolution.recipe.source_url,"vllm-project/recipes/") && strcontains(output.resolution.recipe.source_url,"models/RecursiveSI/flint.yaml")
  error_message="Resolve the live recipe owner/path, without a static alias catalog or legacy source fallback."
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
