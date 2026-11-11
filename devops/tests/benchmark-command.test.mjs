// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
const script=resolve(import.meta.dirname,'../benchmark.sh');
test('official benchmark receives frozen tokenizer, bounded load and native result options',()=>{
  const dir=mkdtempSync(`${tmpdir()}/oke-benchmark-command-`);
  try {
    const config={mode:'benchmark',model:'org/model',model_revision:'a'.repeat(40),context_length:4096,concurrency:4,benchmark_requests:20,benchmark_input_tokens:1024,benchmark_output_tokens:128,base_url:'http://router'};
    writeFileSync(`${dir}/config.json`,JSON.stringify(config));
    writeFileSync(`${dir}/hf`,'#!/bin/bash\nprintf "%s\\n" "$@" > "$CAPTURE/hf-args"\n',{mode:0o755});
    writeFileSync(`${dir}/vllm`,'#!/bin/bash\nprintf "%s\\n" "$@" > "$CAPTURE/vllm-args"\nwhile [[ $# -gt 0 ]]; do if [[ "$1" == --result-dir ]]; then shift; result_dir=$1; fi; shift; done\nprintf \'{"completed":20,"errors":[]}\\n\' > "$result_dir/result.json"\n',{mode:0o755});
    const env={...process.env,PATH:`${dir}:${process.env.PATH}`,CAPTURE:dir};
    const output=execFileSync('bash',[script,`${dir}/config.json`],{env,encoding:'utf8'});
    const args=readFileSync(`${dir}/vllm-args`,'utf8').trim().split('\n');
    assert.deepEqual(args.slice(0,2),['bench','serve']);
    for(const [flag,value] of [['--max-concurrency','4'],['--num-prompts','20'],['--random-input-len','1024'],['--random-output-len','128'],['--backend','openai-chat'],['--served-model-name','model']]) assert.equal(args[args.indexOf(flag)+1],value);
    assert.ok(args.includes('--save-detailed'));
    assert.match(readFileSync(`${dir}/hf-args`,'utf8'),new RegExp(config.model_revision));
    assert.match(output,/BENCHMARK_RESULT_BEGIN\n\{"completed":20/);
    writeFileSync(`${dir}/config.json`,JSON.stringify({...config,benchmark_input_tokens:4000}));
    const invalid=spawnSync('bash',[script,`${dir}/config.json`],{env,encoding:'utf8'});
    assert.equal(invalid.status,2);
    assert.match(invalid.stderr,/exceed context/);
  } finally {rmSync(dir,{recursive:true,force:true});}
});
