#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Runs in the official pinned vLLM CPU client image. No serving GPU is requested.
set -euo pipefail
hf download "$MODEL_ID" --revision "$MODEL_REVISION" --local-dir "${BENCHMARK_TOKENIZER_DIR:-/tmp/tokenizer}" \
  --include tokenizer.json --include tokenizer_config.json --include tokenizer.model --include sentencepiece.bpe.model \
  --include spiece.model --include vocab.json --include vocab.txt --include merges.txt --include special_tokens_map.json \
  --include added_tokens.json --include chat_template.jinja --include config.json
exec python3 "$(dirname "${BASH_SOURCE[0]}")/benchmark.py"
