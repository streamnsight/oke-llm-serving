// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'../..');
const header='#!/usr/bin/env node\n';
const fake=header+`
import fs from 'node:fs';
const args=process.argv.slice(2), command=args.join(' '), flag=k=>args[args.indexOf(k)+1];
fs.appendFileSync(process.env.CLI_TEST_LOG,JSON.stringify(args)+'\\n');
const scenario=process.env.CLI_TEST_SCENARIO;
if(scenario==='failure'&&command.includes('limits value list')) {process.stderr.write('fixture API denied\\n');process.exit(1);}
if(args.includes('--auth')&&flag('--auth')==='instance_obo_user') {
 const config=fs.readFileSync(flag('--config-file'),'utf8');
 if(!config.includes('delegation_token_file=')||config.includes('fixture-secret-token'))throw Error('unsafe config');
}
let data;
if(command.includes('region-subscription list')) data=scenario==='batch-four'?[1,2,3,4].map(n=>({'region-name':'region-'+n,status:'READY','is-home-region':n===1})):[{'region-name':'new-region-99',status:'READY','is-home-region':true},{'region-name':'not-ready',status:'IN_PROGRESS'}];
else if(command.includes('availability-domain list')) data=[{name:'AD-1'}];
else if(command.includes('compute shape list')) data=[{shape:'VM.GPU.A10.1',gpus:1,'gpu-description':'A10','memory-in-gbs':240,ocpus:15,'quota-names':['gpu-a10-count']}];
else if(command.includes('limits definition list'))data=[{name:'gpu-a10-count','is-resource-availability-supported':true}];
else if(command.includes('limits value list')) data=scenario==='unmapped'?[]:[{name:'gpu-a10-count','scope-type':'AD','availability-domain':scenario==='other-ad-zero'?'AD-2':'AD-1',value:['zero','other-ad-zero'].includes(scenario)?0:8}];
else if(command.includes('resource-availability get'))data={available:8,used:0};
else if(command.includes('compute-capacity-report create')) {
 const request=JSON.parse(fs.readFileSync(flag('--shape-availabilities').replace('file://',''),'utf8'));
 if(request[0].instanceShape!=='VM.GPU.A10.1')throw Error('wrong report request');
 data={'time-created':'2026-11-11T00:00:00Z','shape-availabilities':scenario==='missing'?[]:[{'instance-shape':'VM.GPU.A10.1','availability-status':'AVAILABLE','available-count':scenario==='unknown'?null:2}]};
} else throw Error('Unexpected command: '+command);
process.stdout.write(JSON.stringify({data}));
`;
function run(scenario='',overrides={},extraEnv={}) {
 const dir=mkdtempSync(`${tmpdir()}/oke-cli-test-`);
 try {
  mkdirSync(`${dir}/bin`);writeFileSync(`${dir}/bin/oci`,fake,{mode:0o755});
  const q={tenancy_ocid:'tenancy',compartment_id:'target',region:'bootstrap',regions:'[]',shape_names:'[]',query_resource_availability:'true',only_shapes_with_limits:'false',observation_id:'test',gpu_catalog:JSON.stringify({source:'fixture',shapes:{'VM.GPU.A10.1':{memory_bytes_per_gpu:24000000000}}}),...overrides};
  const proc=spawnSync('bash',[`${root}/scripts/discover-oci.sh`],{input:JSON.stringify(q),encoding:'utf8',env:{...process.env,TF_VAR_auth:'',OCI_AUTH:'',OCI_RESOURCE_PRINCIPAL_VERSION:'',OCI_CLI_AUTH:'',PATH:`${dir}/bin:${process.env.PATH}`,CLI_TEST_LOG:`${dir}/calls`,CLI_TEST_SCENARIO:scenario,...extraEnv}});
  const calls=(()=>{try{return readFileSync(`${dir}/calls`,'utf8').trim().split('\n').map(JSON.parse);}catch{return [];}})();
  const result=proc.status===0?JSON.parse(JSON.parse(proc.stdout).result):null;
  return {...proc,result,calls};
 }finally{rmSync(dir,{recursive:true,force:true});}
}
test('CLI discovers future subscriptions and preserves numeric planner observations',()=>{
 const r=run();assert.equal(r.status,0,r.stderr);assert.deepEqual(r.result.assessed_regions,['new-region-99']);
 const row=r.result.regions[0];assert.equal(row.inventory.compartment_id,'target');assert.equal(row.inventory.availability_domains[0].shapes[0].gpu_memory_bytes_per_gpu,24000000000);
 assert.equal(row.capacity.availability_domains[0].assessment.shapes[0].reported_sufficient,true);
 assert.equal(row.inventory.headroom_queries_used,1);
 for(const call of r.calls.filter(c=>c.includes('shape')||c.includes('definition')||c.includes('value')))assert.ok(call.includes('--all'));
 assert.equal(r.calls.filter(c=>c.includes('shape')).length,2,'separate compartment inventory and tenancy physical shapes');
});
test('known zero skips reports; unmapped or another AD zero does not',()=>{
 for(const [scenario,expected] of [['zero',0],['unmapped',1],['other-ad-zero',1]]) {
  const r=run(scenario,{only_shapes_with_limits:'true'});assert.equal(r.status,0,r.stderr);
  assert.equal(r.calls.filter(c=>c.includes('compute-capacity-report')).length,expected,scenario);
 }
});
test('unknown counts and missing report rows remain partial',()=>{
 for(const scenario of ['unknown','missing']) {
  const r=run(scenario);assert.equal(r.status,0,r.stderr);const assessment=r.result.regions[0].capacity.availability_domains[0].assessment;
  assert.equal(assessment.status,'partial');
  if(scenario==='unknown')assert.equal(assessment.shapes[0].reported_sufficient,null);
  else assert.deepEqual(assessment.missing_shapes,['VM.GPU.A10.1']);
 }
});
test('CLI/API errors and non-ready requests fail without publishing capacity',()=>{
 const r=run('failure');assert.notEqual(r.status,0);assert.equal(r.stdout,'');assert.match(r.stderr,/fixture API denied/);
 const requested=run('',{regions:'["not-ready"]'});assert.notEqual(requested.status,0);assert.equal(requested.stdout,'');
});
test('RMS delegated auth uses private token-file config and never exposes token',()=>{
 const r=run('',{}, {TF_VAR_auth:'InstancePrincipal',use_obo_token:'true',obo_token:'fixture-secret-token'});
 assert.equal(r.status,0,r.stderr);assert.ok(r.calls.every(c=>c.includes('instance_obo_user')));
 assert.ok(!JSON.stringify(r).includes('fixture-secret-token'));
});

test('a complete four-region batch publishes every region with no trailing jobs',()=>{
 const r=run('batch-four');assert.equal(r.status,0,r.stderr);assert.equal(r.result.regions.length,4);
 assert.deepEqual(r.result.regions.map(r=>r.inventory.region),['region-1','region-2','region-3','region-4']);
});

test('home region is discovered even when the local caller omits a connection region',()=>{
 const r=run('',{region:''});assert.equal(r.status,0,r.stderr);assert.equal(r.result.home_region,'new-region-99');
 const subscriptions=r.calls.filter(c=>c.includes('region-subscription'));
 assert.equal(subscriptions[0].includes('--region'),false,'first request uses CLI defaults');
 assert.equal(subscriptions[1][subscriptions[1].indexOf('--region')+1],'new-region-99','home region handles subscription discovery');
});

test('blank RMS scope list entries mean no filter',()=>{
 const r=run('',{regions:'["", "  "]',shape_names:'[" "]'});assert.equal(r.status,0,r.stderr);assert.deepEqual(r.result.assessed_regions,['new-region-99']);assert.equal(r.result.regions[0].inventory.availability_domains[0].shapes.length,1);
});
