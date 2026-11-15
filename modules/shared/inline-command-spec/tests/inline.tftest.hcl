# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variables {
  specification = { version = "0.1", component = "command", shell = "bash", env = { variables = { SETTING = "$${SETTING}" } }, inputArtifacts = [], steps = [{ type = "Command", name = "run", command = "bash ./run.sh" }] }
  files         = { "run.sh" = "printf '%s\\n' 'hello'\n", "data/config.json" = "{}" }
}
run "readable_inline_files_preserve_the_original_specification" {
  command = plan
  assert {
    condition     = length(yamldecode(output.content).steps) == 2 && yamldecode(output.content).steps[1].command == "bash ./run.sh" && yamldecode(output.content).env.variables.SETTING == "$${SETTING}" && strcontains(output.preparation_command, "<<'OKE_LLM_") && strcontains(output.preparation_command, "truncate -s -1 -- 'data/config.json'") && !strcontains(output.preparation_command, "base64") && output.encoded_size == length(base64encode(output.content))
    error_message = "Keep readable commands and editable environment bindings; materialization must preserve missing final newlines without encoded script blobs."
  }
}
run "empty_files_leave_the_steps_unchanged" {
  command = plan
  variables { files = {} }
  assert {
    condition     = length(yamldecode(output.content).steps) == 1 && yamldecode(output.content).steps[0].name == "run"
    error_message = "An empty file map must not add an unused preparation step."
  }
}
run "reject_path_traversal" {
  command = plan
  variables { files = { "../escape" = "bad" } }
  expect_failures = [output.content]
}
run "reject_shell_syntax_in_paths" {
  command = plan
  variables { files = { "bad'$(touch injected)" = "bad" } }
  expect_failures = [output.content]
}
run "reject_oversized_serialized_specs" {
  command = plan
  variables { files = { "large.txt" = join("", [for i in range(1024) : "12345678901234567890123456789012345678901234567890"]) } }
  expect_failures = [output.content]
}
run "measure_utf8_bytes_not_unicode_character_count" {
  command = plan
  variables { files = { "unicode.txt" = join("", [for i in range(1024) : "ééééééééééééééééééééééééé"]) } }
  expect_failures = [output.content]
}

run "reject_encoded_transport_overflow_with_decoded_content_below_limit" {
  command = plan
  variables {
    files         = {}
    specification = { steps = [{ type = "Command", command = join("", [for i in range(1000) : "0123456789012345678901234567890123456789"]) }] }
  }
  assert {
    condition     = output.byte_size < 51200 && output.encoded_size > 51200
    error_message = "This regression must exercise an encoded-field overflow that decoded-only accounting misses."
  }
  expect_failures = [output.content]
}

run "accept_exact_encoded_field_boundary" {
  command = plan
  variables {
    files = {}
    specification = {
      steps   = []
      padding = substr(join("", [for i in range(1024) : "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"]), 0, 38400 - length(yamlencode({ steps = [], padding = "" })))
    }
  }
  assert {
    condition     = output.byte_size == 38400 && output.encoded_size == 51200
    error_message = "A 38400-byte complete ASCII document fits the 51200-character transport field exactly."
  }
}
run "reject_first_encoded_field_boundary_overflow" {
  command = plan
  variables {
    files = {}
    specification = {
      steps   = []
      padding = substr(join("", [for i in range(1024) : "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"]), 0, 38401 - length(yamlencode({ steps = [], padding = "" })))
    }
  }
  assert {
    condition     = output.byte_size == 38401 && output.encoded_size == 51204
    error_message = "One more decoded byte crosses the encoded field budget."
  }
  expect_failures = [output.content]
}
