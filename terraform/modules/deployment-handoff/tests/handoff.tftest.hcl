# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variables {
  observation_id = "snapshot"
  profile = {
    model  = { repository = "org/model", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", unused_report_text = "very large report" }
    memory = { assumptions = { context_length = 4096, concurrency = 4, kv_dtype = "bfloat16", runtime_allowance_gib = 2, safety_margin_fraction = 0.2 } }
  }
  serving_configuration = {
    status = "resolved_requires_validation", model = { repository = "org/model", resolved_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, engine = { image = "repo@sha256:frozen" },
    recipe = { args = ["--parser", "example"], env = { UNICODE = "日本語" }, feature_options = { feature = { args = ["--flag"] } }, source_commit = "immutable", api = { url = "https://example/recipe.json", sha256 = "sourcehash", original_argv = ["duplicate"] } }
  }
  assessment = { suggestions = [{ id = "one", region = "region", gpu_shape = "gpu", node_count = 1, configuration_status = "suggested_requires_validation", diagnostics = "unused" }] }
}
run "one_compact_choice_preserves_runtime_and_source_evidence" {
  command = plan
  assert {
    condition     = output.handoffs.one.inline_json != null && output.handoffs.one.bytes < 8000 && jsondecode(output.handoffs.one.inline_json).discovery.assessment.suggestions[0].serving_configuration.recipe.env.UNICODE == "日本語" && !can(jsondecode(output.handoffs.one.inline_json).discovery.assessment.suggestions[0].diagnostics)
    error_message = "Keep launch settings, feature options and immutable provenance, not unrelated report diagnostics."
  }
  assert {
    condition     = output.handoffs.one.bytes > length(output.handoffs.one.inline_json) && !can(jsondecode(output.handoffs.one.inline_json).discovery.assessment.suggestions[0].serving_configuration.recipe.api.original_argv)
    error_message = "Count UTF-8 bytes, not characters; remove only redundant argv evidence."
  }
}
run "oversize_payload_is_not_truncated" {
  command = plan
  variables {
    serving_configuration = { recipe = { args = [join("", [for i in range(1024) : "0123456789"])], env = {}, api = {} } }
  }
  assert {
    condition     = output.handoffs.one.inline_json == null && output.handoffs.one.transport == "object_storage_required" && length(jsondecode(output.handoffs.one.object_json).discovery.assessment.suggestions[0].serving_configuration.recipe.args[0]) == 10240
    error_message = "Oversize frozen configurations must use object transport without losing any command settings."
  }
}
