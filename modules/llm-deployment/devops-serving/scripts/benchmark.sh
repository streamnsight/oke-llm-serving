#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Runs inside the pinned official vLLM CPU image; no GPU is requested.
set -euo pipefail
config=${1:-/benchmark/config.json}
result_dir=$(mktemp -d)
model=$(jq -r .model "$config")
revision=$(jq -r .model_revision "$config")
mode=$(jq -r .mode "$config")
context=$(jq -r .context_length "$config")
concurrency=$(jq -r .concurrency "$config")
if [[ "$mode" == validate ]]; then
  requests=$concurrency
  output_tokens=16
  input_tokens=$((context-output_tokens-128))
else
  requests=$(jq -r .benchmark_requests "$config")
  output_tokens=$(jq -r .benchmark_output_tokens "$config")
  input_tokens=$(jq -r .benchmark_input_tokens "$config")
fi
# Reserve chat-template space. Explicit benchmark inputs are never truncated.
[[ "$input_tokens" -gt 0 && $((input_tokens+output_tokens+128)) -le "$context" ]] || {
  echo 'Benchmark input/output tokens plus 128 template tokens exceed context.' >&2; exit 2;
}
hf download "$model" --revision "$revision" --local-dir /tmp/tokenizer \
  --include tokenizer.json tokenizer_config.json tokenizer.model sentencepiece.bpe.model \
  spiece.model vocab.json vocab.txt merges.txt special_tokens_map.json added_tokens.json chat_template.jinja config.json
vllm bench serve \
  --backend openai-chat --base-url "$(jq -r .base_url "$config")" \
  --endpoint /v1/chat/completions --model "$model" --served-model-name model \
  --tokenizer /tmp/tokenizer --dataset-name random --seed 0 \
  --random-input-len "$input_tokens" --random-output-len "$output_tokens" \
  --random-range-ratio 0 --random-prefix-len 0 --ignore-eos \
  --num-prompts "$requests" --max-concurrency "$concurrency" --request-rate inf \
  --extra-body '{"chat_template_kwargs":{"enable_thinking":false}}' \
  --num-warmups 1 --disable-tqdm --save-result --save-detailed \
  --percentile-metrics ttft,tpot,itl,e2el --metric-percentiles 50,90,95,99 \
  --result-dir "$result_dir" --result-filename result.json
printf '\nBENCHMARK_RESULT_BEGIN\n'
cat "$result_dir/result.json"
printf '\nBENCHMARK_RESULT_END\n'
