// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
const root=resolve(import.meta.dirname,'../..');
test('selection exports immutable deployment identity, nodes and checkpoint-sized storage',()=>{
 const dir=mkdtempSync(`${tmpdir()}/oke-select-`);
 try{
  const discovery={observation_id:'test',profile:{model:{repository:'org/model',resolved_revision:'a'.repeat(40)},weights:{tensor_data_bytes:400000000000},memory:{assumptions:{context_length:4096,concurrency:4,kv_dtype:'bfloat16'}}},assessment:{candidates:[{id:'candidate',region:'region-one',availability_domain:'AD-1',gpu_shape:'BM.GPU4.8',node_count:2,requires_rdma:true,tensor_parallel_size:8,pipeline_parallel_size:2,replicas:1,engine:{image:'vllm/vllm-openai@sha256:'+'b'.repeat(64),version:'0.32.0'}}]}};
  const target=Object.fromEntries(['tenancy_ocid','compartment_id','cluster_id','subnet_id','gpu_image_id','cpu_image_id','cpu_subnet_id','devops_subnet_id','name'].map(key=>[key,'fixture']));
  writeFileSync(`${dir}/discovery.json`,JSON.stringify(discovery));writeFileSync(`${dir}/target.json`,JSON.stringify(target));
  const result=JSON.parse(execFileSync('bash',[`${root}/scripts/select-deployment.sh`,`${dir}/discovery.json`,'candidate',`${dir}/target.json`],{encoding:'utf8'}));
  assert.equal(result.node_count,2);assert.equal(result.model_revision,'a'.repeat(40));assert.ok(result.boot_volume_gib>500);
  assert.throws(()=>execFileSync('bash',[`${root}/scripts/select-deployment.sh`,`${dir}/discovery.json`,'unknown',`${dir}/target.json`],{stdio:'pipe'}));
 }finally{rmSync(dir,{recursive:true,force:true});}
});

test('an undetermined GPU option requires explicit expert settings and freezes dynamic image/args',()=>{
 const dir=mkdtempSync(`${tmpdir()}/oke-select-expert-`);
 try {
  const target=Object.fromEntries(['tenancy_ocid','compartment_id','cluster_id','subnet_id','gpu_image_id','cpu_image_id','cpu_subnet_id','devops_subnet_id','name'].map(key=>[key,'fixture']));
  const image='vllm/vllm-openai@sha256:'+'e'.repeat(64);
  const discovery={observation_id:'test',profile:{model:{repository:'RecursiveSI/flint',resolved_revision:'a'.repeat(40)},weights:{tensor_data_bytes:79570574912},memory:{assumptions:{context_length:4096,concurrency:4,kv_dtype:'bfloat16'}}},serving_configuration:{status:'resolved_requires_validation',model:{repository:'RecursiveSI/flint',resolved_revision:'a'.repeat(40)},engine:{image,version:'0.33.0'},recipe:{args:['--reasoning-parser','glm47'],env:{TEST_SETTING:'value'}}},assessment:{candidates:[],sizing_options:[{id:'option',region:'region-one',availability_domain:'AD-1',gpu_shape:'VM.GPU.A10.1',gpus_per_node:1,configuration_status:'undetermined_requires_expert'}]}};
  writeFileSync(`${dir}/discovery.json`,JSON.stringify(discovery));
  const select=()=>JSON.parse(execFileSync('bash',[`${root}/scripts/select-deployment.sh`,`${dir}/discovery.json`,'option',`${dir}/target.json`],{encoding:'utf8',stdio:['pipe','pipe','pipe']}));
  writeFileSync(`${dir}/target.json`,JSON.stringify(target));assert.throws(select);
  Object.assign(target,{expert_configuration:true});writeFileSync(`${dir}/target.json`,JSON.stringify(target));assert.throws(select);
  Object.assign(target,{tensor_parallel_size:1,pipeline_parallel_size:8,node_count:8,replicas:1,expert_rank_memory_gib:20});writeFileSync(`${dir}/target.json`,JSON.stringify(target));
  const result=select();assert.equal(result.engine_image,image);assert.equal(result.engine_version,'0.33.0');assert.equal(result.node_count,8);assert.equal(result.expert_configuration,true);
  assert.deepEqual(result.engine_args,['--reasoning-parser','glm47']);assert.equal(result.engine_env.TEST_SETTING,'value');assert.equal(result.serving_configuration.model.resolved_revision,'a'.repeat(40));
  target.engine_image='custom.registry/model@sha256:'+'f'.repeat(64);target.engine_version='nightly';target.engine_platform='linux/amd64';
  writeFileSync(`${dir}/target.json`,JSON.stringify(target));const overridden=select();assert.equal(overridden.engine_image,target.engine_image);assert.equal(overridden.serving_configuration.engine.image,target.engine_image);assert.equal(overridden.engine_platform,undefined);

 }finally{rmSync(dir,{recursive:true,force:true});}
});
