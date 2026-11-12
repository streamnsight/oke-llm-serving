// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
const script=resolve(import.meta.dirname,'../terraform/modules/devops-serving/scripts/benchmark-parameters.jq');
const config={benchmark_requests:50,benchmark_input_tokens:256,benchmark_output_tokens:128,context_length:1024};
const run=args=>spawnSync('jq',['-f',script],{input:JSON.stringify({config,arguments:args}),encoding:'utf8'});
test('DevOps benchmark overrides are numeric data with bounded context',()=>{
 const result=run([{name:'BENCHMARK_REQUESTS',value:'100'},{name:'BENCHMARK_INPUT_TOKENS',value:'512'}]);
 assert.equal(result.status,0,result.stderr);
 const parsed=JSON.parse(result.stdout);
 assert.equal(parsed.benchmark_requests,100);assert.equal(parsed.benchmark_input_tokens,512);
 assert.equal(parsed.benchmark_parameter_source,'devops_deployment_arguments');
 assert.equal(JSON.parse(run([]).stdout).benchmark_requests,50);
});
test('invalid counts, duplicates and shell expressions cannot become benchmark commands',()=>{
 for(const args of [
  [{name:'BENCHMARK_REQUESTS',value:'0'}],
  [{name:'BENCHMARK_REQUESTS',value:'10001'}],
  [{name:'BENCHMARK_REQUESTS',value:'1.5'}],
  [{name:'BENCHMARK_INPUT_TOKENS',value:'1024'}],
  [{name:'BENCHMARK_REQUESTS',value:'$(touch /tmp/unwanted)'}],
  [{name:'BENCHMARK_REQUESTS',value:'1'},{name:'BENCHMARK_REQUESTS',value:'2'}]
 ]) assert.notEqual(run(args).status,0);
});
