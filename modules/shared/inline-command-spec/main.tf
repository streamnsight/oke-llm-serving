# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform { required_version = ">= 1.5.0" }
variable "specification" {
  description = "Command specification object with its existing environment, input artifacts and steps."
  type        = any
}
variable "files" {
  description = "Trusted UTF-8 source files materialized as readable, quoted heredocs before the existing steps."
  type        = map(string)
  default     = {}
}
locals {
  delimiters = { for name, content in var.files : name => "OKE_LLM_${substr(sha256("${name}:${content}"), 0, 24)}" }
  preparation_command = join("\n", concat(["set -euo pipefail", "umask 077"], flatten([
    for name in sort(keys(var.files)) : concat([
      "mkdir -p -- '${dirname(name)}'",
      "cat > '${name}' <<'${local.delimiters[name]}'\n${trimsuffix(var.files[name], "\n")}\n${local.delimiters[name]}"
    ], endswith(var.files[name], "\n") ? [] : ["truncate -s -1 -- '${name}'"])
  ])))
  content = yamlencode(merge(var.specification, {
    steps = concat(length(var.files) > 0 ? [{
      type = "Command", name = "prepare-inline-files", shell = "bash", command = local.preparation_command
    }] : [], var.specification.steps)
  }))
  # Measure decoded UTF-8 bytes from the transport representation, without
  # executing any decoding in the command body. Terraform length counts Unicode
  # characters, while OCI applies its limit to decoded bytes.
  encoded_size = length(base64encode(local.content))
  byte_size    = local.encoded_size / 4 * 3 - (endswith(base64encode(local.content), "==") ? 2 : endswith(base64encode(local.content), "=") ? 1 : 0)
}
output "content" {
  value = local.content
  precondition {
    condition = alltrue([for name in keys(var.files) :
      can(regex("^[A-Za-z0-9_-][A-Za-z0-9_./-]*$", name)) && !contains(split("/", name), "..") && !endswith(name, "/")
    ])
    error_message = "Inline file names must be safe relative paths without traversal or shell syntax."
  }
  precondition {
    condition     = alltrue([for name, content in var.files : !contains(split("\n", content), local.delimiters[name])])
    error_message = "Inline content conflicts with its quoted heredoc delimiter."
  }
  precondition {
    condition     = local.byte_size <= 51200
    error_message = "Inline command specification is ${local.byte_size} UTF-8 bytes; OCI allows at most 51200. Keep larger payload assets as Artifact Registry inputs."
  }
}
output "encoded_size" { value = local.encoded_size }
output "byte_size" { value = local.byte_size }
output "preparation_command" { value = local.preparation_command }
