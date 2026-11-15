// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {spawnSync} from 'node:child_process';
const script = new URL('../scripts/cleanup-repository.sh', import.meta.url).pathname;
const repository = 'ocid1.artifactrepository.oc1.fra.fixture';
const fake = `#!/usr/bin/env node
const fs=require('node:fs'), args=process.argv.slice(2), dir=process.env.CLEANUP_TEST_DIR;
const flag=name=>args[args.indexOf(name)+1];
fs.appendFileSync(dir+'/calls',JSON.stringify(args)+'\\n');
if(args.includes('--config-file')) {
 const config=fs.readFileSync(flag('--config-file'),'utf8');
 if(!config.includes('delegation_token_file=')||config.includes('fixture-secret-token'))throw Error('Unsafe delegation config');
 const tokenPath=config.match(/delegation_token_file=(.*)/)[1];
 if(fs.readFileSync(tokenPath,'utf8')!=='fixture-secret-token')throw Error('Missing delegation token');
}
const scenario=process.env.CLEANUP_TEST_SCENARIO, repo=process.env.REPOSITORY_ID;
const state=JSON.parse(fs.readFileSync(dir+'/state','utf8'));
if(args.includes('list')) {
 if(!args.includes('--all')||flag('--repository-id')!==repo||flag('--compartment-id')!=='compartment')throw Error('Unscoped list');
 if(scenario==='list-failure'){process.stderr.write('Authorization failed');process.exit(42);}
 state.lists++;fs.writeFileSync(dir+'/state',JSON.stringify(state));
 const row=(id,status='AVAILABLE')=>({id:'ocid1.genericartifact.oc1.fra.'+id,'repository-id':repo,'lifecycle-state':status});
 let items=[];
 if(scenario==='foreign')items=[{...row('foreign'),'repository-id':'other-repository'}];
 else if(scenario==='forever')items=[row('pending','DELETING')];
 else if(scenario==='already-deleting'&&state.lists===1)items=[row('pending','DELETING')];
 else if(!['empty','already-deleting'].includes(scenario)&&state.lists<=2)items=[row('old-script',state.lists===2&&scenario!=='stale'?'DELETING':'AVAILABLE'),...(state.lists===1?[row('pipeline-result'),row('deleted','DELETED')]:[])];
 process.stdout.write(JSON.stringify(scenario==='malformed'?{data:{}}:{data:{items}}));
} else if(args.includes('delete')) {
 if(!args.includes('--force'))throw Error('Interactive deletion');
 if(scenario==='delete-failure'){process.stderr.write('Delete refused');process.exit(43);}
 state.deleted.push(flag('--artifact-id'));fs.writeFileSync(dir+'/state',JSON.stringify(state));
 process.stdout.write('{}');
} else throw Error('Unexpected OCI command');
`;
function run(scenario='normal',extra={}) {
 const dir=mkdtempSync(`${tmpdir()}/oke-repository-cleanup-`);
 try {
  mkdirSync(dir+'/bin');writeFileSync(dir+'/bin/oci',fake,{mode:0o755});
  writeFileSync(dir+'/bin/sleep','#!/bin/sh\nexit 0\n',{mode:0o755});
  writeFileSync(dir+'/state',JSON.stringify({lists:0,deleted:[]}));
  const env={...process.env,REPOSITORY_ID:repository,COMPARTMENT_ID:'compartment',TF_VAR_auth:'',OCI_AUTH:'',OCI_RESOURCE_PRINCIPAL_VERSION:'',OCI_CLI_AUTH:'',TF_VAR_use_obo_token:'',OCI_use_obo_token:'',use_obo_token:'',CLEANUP_TEST_DIR:dir,CLEANUP_TEST_SCENARIO:scenario,PATH:`${dir}/bin:${process.env.PATH}`,...extra};
  const result=spawnSync('bash',[script],{env,encoding:'utf8',timeout:15000});
  let calls=[];try{calls=readFileSync(dir+'/calls','utf8').trim().split('\n').map(JSON.parse);}catch{}
  return {...result,state:JSON.parse(readFileSync(dir+'/state','utf8')),calls};
 }finally{rmSync(dir,{recursive:true,force:true});}
}
test('purges all stored versions including old scripts and pipeline results; polls to empty',()=>{
 const r=run();assert.equal(r.status,0,r.stderr);assert.equal(r.state.deleted.length,2);assert.equal(r.state.lists,3);
 assert.ok(r.calls.every(c=>c[c.indexOf('--region')+1]==='fra'));
});
test('an empty repository needs no deletion',()=>{const r=run('empty');assert.equal(r.status,0,r.stderr);assert.equal(r.state.deleted.length,0);});
test('in-progress and stale deletion observations are polled without repeated deletes',()=>{
 for(const scenario of ['already-deleting','stale']){const r=run(scenario);assert.equal(r.status,0,r.stderr);assert.equal(new Set(r.state.deleted).size,r.state.deleted.length);}
});
test('a repository that stays nonempty stops destroy after bounded retries',()=>{const r=run('forever');assert.notEqual(r.status,0);assert.equal(r.state.lists,12);assert.match(r.stderr,/deletion stopped/);});
test('list/delete failures are fatal rather than treated as an empty repository',()=>{
 for(const [scenario,code] of [['list-failure',42],['delete-failure',43]]){const r=run(scenario);assert.equal(r.status,code);}
});
test('foreign repository responses and malformed collections cannot trigger deletes',()=>{
 for(const scenario of ['foreign','malformed']){const r=run(scenario);assert.notEqual(r.status,0);assert.equal(r.state.deleted.length,0);}
});
test('local profile defaults remain usable and full region names come from repository OCIDs',()=>{
 const r=run('empty',{REPOSITORY_ID:repository.replace('.fra.','.eu-frankfurt-1.')});assert.equal(r.status,0,r.stderr);
 assert.ok(r.calls.every(c=>!c.includes('--auth')&&c[c.indexOf('--region')+1]==='eu-frankfurt-1'));
});
test('RMS delegated authentication reads a private token file without exposing the token',()=>{
 const r=run('empty',{TF_VAR_auth:'InstancePrincipal',TF_VAR_use_obo_token:'true',TF_VAR_obo_token:'fixture-secret-token'});
 assert.equal(r.status,0,r.stderr);assert.ok(r.calls.every(c=>c[c.indexOf('--auth')+1]==='instance_obo_user'));
 assert.ok(!JSON.stringify(r.calls).includes('fixture-secret-token'));assert.ok(!r.stdout.includes('fixture-secret-token'));
});
test('instance and resource principal auth use the expected CLI mode',()=>{
 for(const [mode,expected] of [['InstancePrincipal','instance_principal'],['ResourcePrincipal','resource_principal']]){
  const r=run('empty',{TF_VAR_auth:mode});assert.equal(r.status,0,r.stderr);assert.equal(r.calls[0][r.calls[0].indexOf('--auth')+1],expected);
 }
});
test('missing delegation token and invalid repository fail before any CLI call',()=>{
 for(const extra of [{TF_VAR_auth:'InstancePrincipal',TF_VAR_use_obo_token:'true',TF_VAR_obo_token:''},{REPOSITORY_ID:'invalid'}]){
  const r=run('empty',extra);assert.notEqual(r.status,0);assert.equal(r.calls.length,0);
 }
});
