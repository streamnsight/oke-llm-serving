<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Readable inline command specifications

Pass a command specification object in `specification` and trusted UTF-8 source files in `files`. The `content` output preserves its environment, existing input artifacts and steps, and prepends one Bash step that writes those files through readable, quoted heredocs. No runtime base64 decoding, command evaluation or interpolation of file contents is used. File paths are relative and validated; a deterministic delimiter avoids accidental heredoc termination. Files retain their exact trailing-newline behavior.

OCI accepts at most 51,200 decoded UTF-8 bytes in an inline artifact. The output checks the complete rendered command specification, including YAML, helper files and configuration. `byte_size` measures decoded bytes correctly for non-ASCII text; `encoded_size` measures the API transport field. The caller must use the provider's required `base64encoded_content` field at the API boundary. That transport encoding does not appear inside the decoded command specification.

Keep large runtime/chart source assets as Artifact Registry inputs and charts in OCIR. Do not remove an input artifact until its content is included in `files` or otherwise provided to the command. Settings intended for users remain pipeline parameters/environment variables.
