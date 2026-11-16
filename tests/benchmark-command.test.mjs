// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import{execFileSync}from'node:child_process';
import{mkdtempSync,writeFileSync,readFileSync,rmSync}from'node:fs';
import{tmpdir}from'node:os';
import{resolve}from'node:path';
const script=resolve(import.meta.dirname,'../modules/llm-deployment/model-delivery/scripts/bench-client.sh');
test('official CPU benchmark receives pinned tokenizer and editable bounded native CLI parameters',()=>{
 const dir=mkdtempSync(`${tmpdir()}/model-bench-client-`);
 try{
  writeFileSync(`${dir}/hf`,'#!/bin/bash\nprintf "%s\\n" "$@" > "$CAPTURE/hf-args"\n',{mode:0o755});
  writeFileSync(`${dir}/vllm`,'#!/bin/bash\nprintf "%s\\n" "$@" > "$CAPTURE/vllm-args"\nprintf \'{"completed":20,"errors":[]}\\n\' > "$BENCHMARK_RESULT_DIR/result.json"\n',{mode:0o755});
  const env={...process.env,PATH:`${dir}:${process.env.PATH}`,CAPTURE:dir,MODEL_ID:'org/model',MODEL_REVISION:'a'.repeat(40),BASE_URL:'http://model',CONCURRENCY:'4',BENCHMARK_BACKEND:'openai-chat',BENCHMARK_REQUESTS:'20',BENCHMARK_INPUT_TOKENS:'1024',BENCHMARK_OUTPUT_TOKENS:'128',BENCHMARK_PREFIX_TOKENS:'768',BENCHMARK_RESULT_DIR:`${dir}/result`};
  const output=execFileSync('bash',[script],{env,encoding:'utf8'}),args=readFileSync(`${dir}/vllm-args`,'utf8').trim().split('\n');
  const hfArgs=readFileSync(`${dir}/hf-args`,'utf8').trim().split('\n');
  const patterns=[];
  for(let i=2;i<hfArgs.length;i+=2){
   assert(['--revision','--local-dir','--include'].includes(hfArgs[i]),`Unexpected positional download filename: ${hfArgs[i]}`);
   if(hfArgs[i]==='--include')patterns.push(hfArgs[i+1]);
  }
  assert(patterns.includes('tokenizer.json'));assert(patterns.includes('tokenizer_config.json'));assert(patterns.includes('config.json'));
  assert.deepEqual(args.slice(0,2),['bench','serve']);
  for(const[flag,value]of[['--backend','openai-chat'],['--max-concurrency','4'],['--num-prompts','20'],['--random-input-len','1024'],['--random-output-len','128'],['--served-model-name','org/model'],['--random-prefix-len','768']])assert.equal(args[args.indexOf(flag)+1],value);
  assert(args.includes('--save-detailed'));assert(!args.includes('--extra-body'),'Do not force text-model thinking/chat-template flags onto arbitrary recipes');assert.match(readFileSync(`${dir}/hf-args`,'utf8'),new RegExp(env.MODEL_REVISION));assert.match(output,/BENCHMARK_RESULT_BEGIN\n\{"completed":20/);
 }finally{rmSync(dir,{recursive:true,force:true});}
});

test('Terraform and RMS default to a runnable text benchmark adapter',()=>{
 for(const file of ['modules/llm-deployment/model-delivery/variables.tf','templates/llm-deployment/variables.tf']){
  const source=readFileSync(resolve(import.meta.dirname,'..',file),'utf8');
  assert.match(source,/variable "benchmark_backend" \{[^}]*default\s*=\s*"openai-chat"/);
 }
 assert.match(readFileSync(resolve(import.meta.dirname,'../templates/llm-deployment/schema.yaml'),'utf8'),/benchmark_backend:.*default: openai-chat/);
});
