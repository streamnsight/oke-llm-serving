// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,copyFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..'),scripts=`${root}/modules/llm-deployment/model-delivery/scripts`,runner=`${scripts}/benchmark.py`;
const env={...process.env,CONTEXT_LENGTH:'4096',CONCURRENCY:'4',REPLICAS:'2',BENCHMARK_MODE:'quick',BENCHMARK_REQUESTS:'auto',BENCHMARK_INPUT_TOKENS:'auto',BENCHMARK_OUTPUT_TOKENS:'128',BENCHMARK_PREFIX_TOKENS:'auto',BENCHMARK_MAX_CONCURRENCY:'auto',BENCHMARK_MAX_SECONDS:'auto'};
const plan=overrides=>JSON.parse(execFileSync('python3',[runner,'--plan'],{env:{...env,...overrides},encoding:'utf8'}));
test('quick/full matrices respect context, compare equal total inputs, and bound client work',()=>{
 const quick=plan({});assert.deepEqual(quick.input_tokens,[1024,3840]);assert.deepEqual(quick.shared_prefix_tokens,[768,2880]);assert.equal(quick.requests,64);assert.equal(quick.concurrency,8);assert.equal(quick.measured_requests,256);
 const full=plan({BENCHMARK_MODE:'full',CONTEXT_LENGTH:'32768'});assert.deepEqual(full.input_tokens,[512,1024,2048,4096,8192,16384]);assert.equal(full.requests,512);assert.equal(full.max_seconds,18000);assert(full.job_seconds<21600);
 assert.deepEqual(plan({CONTEXT_LENGTH:'512'}).input_tokens,[256]);
 assert.deepEqual(plan({CONTEXT_LENGTH:'4194304'}).input_tokens,[1024,4096],'A large serving context must not force a large workload or disable benchmarking');
 assert.deepEqual(plan({BENCHMARK_INPUT_TOKENS:'2000,1000,2000',BENCHMARK_PREFIX_TOKENS:'128'}).input_tokens,[1000,2000]);
 for(const value of [{BENCHMARK_INPUT_TOKENS:'4096'},{BENCHMARK_REQUESTS:'$(touch unwanted)'},{BENCHMARK_INPUT_TOKENS:'1,2'},{BENCHMARK_PREFIX_TOKENS:'0'},{BENCHMARK_PREFIX_TOKENS:'1024'},{BENCHMARK_MODE:'everything'},{BENCHMARK_MAX_SECONDS:'20001'},{BENCHMARK_MODE:'full',CONTEXT_LENGTH:'262144',BENCHMARK_INPUT_TOKENS:'65536',BENCHMARK_REQUESTS:'1024'}]){
  const r=spawnSync('python3',[runner,'--plan'],{env:{...env,...value},encoding:'utf8'});assert.equal(r.status,2,r.stderr);assert.match(r.stderr,/Benchmark failed:/);
 }
});
function fixture(){
 const dir=mkdtempSync(`${tmpdir()}/benchmark-matrix-`);mkdirSync(`${dir}/client`);for(const name of ['bench-client.sh','benchmark.py'])copyFileSync(`${scripts}/${name}`,`${dir}/client/${name}`);mkdirSync(`${dir}/vllm/benchmarks`,{recursive:true});
 writeFileSync(`${dir}/vllm/__init__.py`,'');writeFileSync(`${dir}/vllm/benchmarks/__init__.py`,'');
 writeFileSync(`${dir}/transformers.py`,String.raw`
import os
class Tokenizer:
    def __call__(self,prompt):
        return type('Tokens',(),{'input_ids':prompt.split()})()
    def apply_chat_template(self,messages,**kwargs):
        tokens=['user']*int(os.environ.get('TEMPLATE_EXTRA','1'))+messages[0]['content'].split()+['assistant']
        return tokens if kwargs.get('return_dict') is False else {'input_ids':tokens,'attention_mask':[1]*len(tokens)}
class AutoTokenizer:
    @staticmethod
    def from_pretrained(*args,**kwargs): return Tokenizer()
`);
 writeFileSync(`${dir}/vllm/benchmarks/datasets.py`,String.raw`
class RandomDataset:
    def __init__(self,random_seed): self.seed=random_seed
    def sample(self,tokenizer,num_requests,prefix_len,input_len,**kwargs):
        return [type('Sample',(),{'prompt':' '.join([f'p{self.seed}-{j}' for j in range(prefix_len)]+[f'u{self.seed}-{i}-{j}' for j in range(input_len)])})() for i in range(num_requests)]
`);
 mkdirSync(`${dir}/bin`);
 writeFileSync(`${dir}/bin/hf`,'#!/bin/bash\nprintf "%s\\n" "$@" > "$CAPTURE/hf-args"\n',{mode:0o755});
 writeFileSync(`${dir}/bin/vllm`,String.raw`#!/usr/bin/env python3
import sys,os,json,pathlib
a=sys.argv[1:]
def arg(k): return a[a.index(k)+1]
prompts=[json.loads(line)['prompt'] for line in pathlib.Path(arg('--dataset-path')).read_text().splitlines()]
with open(os.environ['CAPTURE']+'/native-calls.jsonl','a') as f: f.write(json.dumps({'args':a,'prompts':prompts})+'\n')
n=int(arg('--num-prompts')); failed=n if os.environ.get('FAIL_PROFILE','none') in arg('--result-dir') else 0
result={'completed':n-failed,'failed':failed,'duration':2,'request_throughput':n/2,'output_throughput':n*2,'total_token_throughput':200,'input_lens':[len(p.split())+2 for p in prompts],'output_lens':[4]*n,'generated_texts':['PRIVATE_GENERATED_TEXT']*n,'errors':['PRIVATE_ERROR_PROMPT']*failed}
for metric in ['ttft','tpot','itl','e2el']:
 for key in ['mean','median']+['p'+str(p) for p in range(90,100)]: result[key+'_'+metric+'_ms']=10 if not failed else 0
pathlib.Path(arg('--result-dir')+'/'+arg('--result-filename')).write_text(json.dumps(result))
print('PRIVATE_NATIVE_DIAGNOSTIC')
sys.exit(7 if failed else 0)
`,{mode:0o755});
 const current={...env,PATH:`${dir}/bin:${process.env.PATH}`,PYTHONPATH:dir,CAPTURE:dir,MODEL_ID:'org/model',MODEL_REVISION:'a'.repeat(40),BASE_URL:'http://model',BENCHMARK_BACKEND:'openai-chat',BENCHMARK_REQUESTS:'4',BENCHMARK_INPUT_TOKENS:'32,64',BENCHMARK_OUTPUT_TOKENS:'4',BENCHMARK_RESULT_DIR:`${dir}/results`};
 return {dir,env:current,run(overrides={}){return spawnSync('bash',[`${dir}/client/bench-client.sh`],{env:{...current,...overrides},encoding:'utf8',timeout:20000});},close(){rmSync(dir,{recursive:true,force:true});}};
}
test('native client measures matched unique/shared cases, warms a separate prompt, logs distributions without private details',()=>{
 const f=fixture();try{
  const r=f.run();assert.equal(r.status,0,r.stderr);const events=r.stdout.split('\n').filter(l=>l.startsWith('{')).map(l=>JSON.parse(l));
  const cases=events.filter(e=>e.event==='benchmark_case_summary');assert.equal(cases.length,4);assert(cases.every(e=>e.completed===4&&e.prefix_cache.status==='unavailable'));assert.deepEqual(cases.map(e=>e.input_tokens),[32,32,64,64]);
  assert(cases.every(e=>Object.keys(e.latency.ttft_ms).length===12));assert.match(r.stdout,/mean=10.000 median=10.000 p90=10.000.*p99=10.000/);assert(!r.stdout.includes('PRIVATE'));assert(!r.stderr.includes('PRIVATE'));
  const hf=readFileSync(`${f.dir}/hf-args`,'utf8').trim().split('\n');assert.equal(hf[hf.indexOf('--revision')+1],f.env.MODEL_REVISION);
  const patterns=[];for(let i=2;i<hf.length;i+=2){assert(['--revision','--local-dir','--include'].includes(hf[i]));if(hf[i]==='--include')patterns.push(hf[i+1]);}assert(patterns.includes('tokenizer_config.json'));assert(patterns.includes('config.json'));
  const calls=readFileSync(`${f.dir}/native-calls.jsonl`,'utf8').trim().split('\n').map(JSON.parse);assert.equal(calls.length,8);
  for(let i=0;i<calls.length;i+=2){
   const warm=calls[i],measured=calls[i+1];assert.equal(warm.prompts.length,1);assert.equal(measured.prompts.length,4);assert(!measured.prompts.includes(warm.prompts[0]));
   const length=i<4?32:64,prefix=i%4===2?length*3/4:0;
   for(const prompt of measured.prompts)assert.equal(prompt.split(' ').length,length);
   if(prefix){const p=warm.prompts[0].split(' ').slice(0,prefix);for(const prompt of measured.prompts)assert.deepEqual(prompt.split(' ').slice(0,prefix),p);}
   const args=measured.args;assert(args.includes('--save-detailed'));assert(args.includes('--skip-chat-template'));assert.equal(args[args.indexOf('--num-warmups')+1],'0');assert.equal(args[args.indexOf('--metric-percentiles')+1],'50,90,91,92,93,94,95,96,97,98,99');assert(!args.includes('--extra-body'));
  }
  assert.equal(events.filter(e=>e.event==='benchmark_cache_comparison').length,2);
 }finally{f.close();}
});
test('actual chat-template expansion is checked before sending an oversized request',()=>{
 const f=fixture();try{const r=f.run({BENCHMARK_INPUT_TOKENS:'128',CONTEXT_LENGTH:'260',TEMPLATE_EXTRA:'200'});assert.equal(r.status,2,r.stderr);assert.match(r.stderr,/Actual tokenized request exceeds deployed context/);assert.throws(()=>readFileSync(`${f.dir}/native-calls.jsonl`),{code:'ENOENT'});}finally{f.close();}
});
test('failed warmup preserves native status and never reports a successful cache comparison',()=>{
 const f=fixture();try{const r=f.run({FAIL_PROFILE:'shared'});assert.equal(r.status,7,r.stderr);assert.match(r.stdout,/benchmark_case_failed/);assert.match(r.stdout,/"phase":"warmup"/);assert(!r.stdout.includes('benchmark_cache_comparison'));assert(!r.stdout.includes('PRIVATE'));}finally{f.close();}
});
test('P/D observations are emitted per case without changing success into a transfer claim',()=>{
 const f=fixture();try{
  writeFileSync(`${f.dir}/targets.json`,JSON.stringify([{url:'http://prefill/metrics',role:'prefill',pod:'p'},{url:'http://decode/metrics',role:'decode',pod:'d'}]));
  let r=f.run({BENCHMARK_PD_ENABLED:'true',BENCHMARK_METRICS_TARGETS_FILE:`${f.dir}/targets.json`});assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/"pd_transfer":\{"status":"unknown"/);
  writeFileSync(`${f.dir}/client/pd_observe.py`,"def snapshot(targets): return targets\ndef delta(before,after): return {'status':'transfer_observed','roles':{'decode':{'bytes':1024}}}\n");
  r=f.run({BENCHMARK_PD_ENABLED:'true',BENCHMARK_METRICS_TARGETS_FILE:`${f.dir}/targets.json`});assert.equal(r.status,0,r.stderr);const summaries=r.stdout.split('\n').filter(l=>l.startsWith('{')).map(l=>JSON.parse(l)).filter(e=>e.event==='benchmark_case_summary');assert.equal(summaries.length,4);assert(summaries.every(e=>e.pd_transfer.status==='transfer_observed'&&e.pd_transfer.roles.decode.bytes===1024));
 }finally{f.close();}
});
test('empty distributions and counter resets stay unknown rather than showing fabricated performance',()=>{
 const code=`import importlib.util,json\ns=importlib.util.spec_from_file_location('bench',${JSON.stringify(runner)});m=importlib.util.module_from_spec(s);s.loader.exec_module(m)\nprint(json.dumps([m.summarize({'completed':0,'failed':4,'mean_ttft_ms':0},4),m.counter_delta([{'queries':10,'hits':5}],[{'queries':2,'hits':1}]),m.counter_delta([{'queries':10,'hits':5}],[{'queries':20,'hits':13}])]))`;
 const [empty,reset,observed]=JSON.parse(execFileSync('python3',['-c',code],{encoding:'utf8'}));assert.equal(empty.latency.ttft_ms.mean,null);assert.equal(empty.requests_per_second,null);assert.equal(reset.status,'reset');assert.equal(observed.queries,10);assert.equal(observed.hits,8);assert.equal(observed.hit_ratio,.8);
});
test('Terraform and RMS expose quick/full while retaining the text task adapter',()=>{
 for(const file of ['modules/llm-deployment/model-delivery/variables.tf','templates/llm-deployment/variables.tf']){const source=readFileSync(`${root}/${file}`,'utf8');assert.match(source,/variable "benchmark_backend" \{[^}]*default\s*=\s*"openai-chat"/);assert.match(source,/variable "benchmark_mode" \{[^}]*default\s*=\s*"quick"/);}
 assert.match(readFileSync(`${root}/templates/llm-deployment/schema.yaml`,'utf8'),/benchmark_mode:.*enum: \[ quick, full \]/);
});
