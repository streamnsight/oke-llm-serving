#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Runs in the official pinned vLLM CPU client image. No serving GPU is requested.
set -euo pipefail
result_dir=${BENCHMARK_RESULT_DIR:-/tmp/benchmark}
mkdir -p "$result_dir"
hf download "$MODEL_ID" --revision "$MODEL_REVISION" --local-dir /tmp/tokenizer \
  --include tokenizer.json --include tokenizer_config.json --include tokenizer.model --include sentencepiece.bpe.model \
  --include spiece.model --include vocab.json --include vocab.txt --include merges.txt --include special_tokens_map.json \
  --include added_tokens.json --include chat_template.jinja --include config.json
endpoint=/v1/completions
[[ $BENCHMARK_BACKEND != openai-chat ]] || endpoint=/v1/chat/completions
vllm bench serve --backend "$BENCHMARK_BACKEND" --base-url "$BASE_URL" --endpoint "$endpoint" \
  --model "$MODEL_ID" --served-model-name "$MODEL_ID" --tokenizer /tmp/tokenizer \
  --dataset-name random --seed 0 --random-input-len "$BENCHMARK_INPUT_TOKENS" --random-output-len "$BENCHMARK_OUTPUT_TOKENS" \
  --random-range-ratio 0 --random-prefix-len 0 --ignore-eos --num-prompts "$BENCHMARK_REQUESTS" \
  --max-concurrency "$CONCURRENCY" --request-rate inf --num-warmups 1 --disable-tqdm \
  --save-result --save-detailed --percentile-metrics ttft,tpot,itl,e2el --metric-percentiles 50,90,95,99 \
  --result-dir "$result_dir" --result-filename result.json
printf '\nBENCHMARK_RESULT_BEGIN\n'
cat "$result_dir/result.json"
printf '\nBENCHMARK_RESULT_END\n'
