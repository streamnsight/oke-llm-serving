// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {parse} from 'yaml';
const root=resolve(import.meta.dirname,'..');
test('release packaging publishes only the entry discovery archive',()=>{
 const workflow=parse(readFileSync(`${root}/.github/workflows/package-stacks.yaml`,'utf8'));
 const uploads=workflow.jobs.package.steps.filter(s=>s.uses?.startsWith('actions/upload-artifact@'));
 assert.deepEqual(uploads.map(s=>s.with.path),['work/packages/oke-llm-discovery.zip']);
});
test('RMS takes a direct model ID without a static catalog selector',()=>{
 const schema=parse(readFileSync(`${root}/schema.yaml`,'utf8'));
 assert.equal(schema.variables.model.type,'string');assert.equal(schema.variables.model.required,true);assert.equal(schema.variables.model_choice,undefined);
});
test('RMS scope filters use optional list controls with typed items',()=>{
 const schema=parse(readFileSync(`${root}/schema.yaml`,'utf8'));
 for(const name of['regions','shape_names']){assert.equal(schema.variables[name].required,false);assert.equal(schema.variables[name].type,'list');assert.equal(schema.variables[name].default,'[]');const item=schema.variables[schema.variables[name].valueType];assert(item);assert.equal(item.visible,false);}
});
test('RMS groups reference defined variables in discovery and both generated layers',()=>{
 for(const stack of['.','templates/llm-deployment','templates/infrastructure']){const schema=parse(readFileSync(`${root}/${stack}/schema.yaml`,'utf8'));for(const group of schema.variableGroups)for(const name of group.variables){assert.match(name,/^[A-Za-z_][A-Za-z0-9_]*$/);assert(Object.hasOwn(schema.variables,name),`${stack}:${name}`);}}
 const schema=parse(readFileSync(`${root}/schema.yaml`,'utf8'));assert.equal(schema.variables.region.visible,false);
});
test('infrastructure form exposes GPU allocation without model or CPU-pool inputs',()=>{
 const schema=parse(readFileSync(`${root}/templates/infrastructure/schema.yaml`,'utf8'));
 const variables=[...readFileSync(`${root}/templates/infrastructure/variables.tf`,'utf8').matchAll(/variable "([^"]+)"/g)].map(m=>m[1]).sort();
 const helpers=new Set(Object.values(schema.variables).map(v=>v.valueType).filter(Boolean));assert.deepEqual(Object.keys(schema.variables).filter(k=>!helpers.has(k)).sort(),variables);
 for(const name of['model','discovery_json','engine_image','cpu_image_id','cpu_node_count'])assert.equal(schema.variables[name],undefined);
 assert.equal(schema.variables.skip_gpu_allocation.default,false);assert.equal(schema.variables.cluster_id.type,'oci:container:cluster:id');assert.equal(schema.variables.rdma_mode.default,'auto');
});
test('discovery asks for model assessment, while generated model forms own runtime overrides',()=>{
 const discovery=parse(readFileSync(`${root}/schema.yaml`,'utf8')),model=parse(readFileSync(`${root}/templates/llm-deployment/schema.yaml`,'utf8'));
 for(const name of['engine_image','engine_version','engine_platform','recipe_features','kv_dtype'])assert.equal(discovery.variables[name],undefined);
 for(const name of['serving_image','tensor_parallel_size','pipeline_parallel_size','context_length','concurrency'])assert(Object.hasOwn(model.variables,name));
});
test('discovery exposes replica quantity and KV-aware routing alongside per-replica workload',()=>{
 const schema=parse(readFileSync(`${root}/schema.yaml`,'utf8'));
 assert.equal(schema.variables.replicas.type,'integer');assert.equal(schema.variables.replicas.default,1);assert.equal(schema.variables.replicas.minimum,1);
 assert(schema.variableGroups.find(g=>g.title==='Model and workload').variables.includes('replicas'));
 assert(schema.variables.routing_mode.enum.includes('kvaware'));assert.equal(schema.variables.routing_mode.default,'auto');
});
