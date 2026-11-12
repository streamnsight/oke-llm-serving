// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { parseAllDocuments, parse } from 'yaml';
const root = resolve(import.meta.dirname, '../..');
const engines = JSON.parse(readFileSync(`${root}/catalogs/engines.json`));
const components = JSON.parse(readFileSync(`${root}/catalogs/components.json`));
const base = { specification_hash:'b'.repeat(64),name:'fixture',namespace:'fixture',model:'org/model',model_revision:'a'.repeat(40),engine_image:engines.engines[0].image,engine_version:engines.engines[0].version,kv_dtype:'bfloat16',tensor_parallel_size:1,pipeline_parallel_size:1,replicas:1,context_length:4096,concurrency:4,requires_rdma:false,components,job_name:'fixture-test' };
const render = config => JSON.parse(execFileSync('jq', ['-f', `${root}/devops/render.jq`], { input:JSON.stringify(config), encoding:'utf8' }));
function checkPod(pod) {
  const spec = pod.spec;
  assert.equal(new Set((spec.volumes??[]).map(v=>v.name)).size, (spec.volumes??[]).length, 'duplicate volume names');
  for(const container of spec.containers) {
    assert.equal(new Set((container.volumeMounts??[]).map(v=>v.mountPath)).size,(container.volumeMounts??[]).length,'duplicate mount paths');
    assert.match(container.image, /@sha256:[a-f0-9]{64}$/);
  }
}
test('distributed groups have correct ranks, anti-affinity, RDMA requests and pinned images',()=>{
  const result=render({...base,pipeline_parallel_size:2,replicas:2,requires_rdma:true});
  assert.equal(result.helm_values.servingEngineSpec.enableEngine,false);
  const lws=result.multi_node_manifest.items[0];
  assert.equal(lws.spec.replicas,2); assert.equal(lws.spec.leaderWorkerTemplate.size,2);
  const leader=lws.spec.leaderWorkerTemplate.leaderTemplate, worker=lws.spec.leaderWorkerTemplate.workerTemplate;
  checkPod(leader);checkPod(worker);
  assert.ok(worker.spec.containers[0].args.includes('--headless'));
  assert.ok(worker.spec.containers[0].args.includes('$(LWS_WORKER_INDEX)'));
  assert.equal(leader.spec.containers[0].resources.requests['rdma/rdma_shared_device_a'],1);
  assert.ok(leader.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution.length);
  assert.equal(result.multi_node_manifest.items[2].spec.selector['leaderworkerset.sigs.k8s.io/group-index'],'1');
  assert.equal(result.helm_values.routerSpec.staticModels,'model,model');
  assert.equal(result.benchmark_job.spec.template.spec.containers[0].resources.requests['nvidia.com/gpu'],undefined);
  checkPod(result.benchmark_job.spec.template);
  const benchmark=result.benchmark_job.spec.template.spec.containers[0];
  assert.match(benchmark.image,/^vllm\/vllm-openai-cpu@sha256:/);
  assert.deepEqual(benchmark.command,['bash','/benchmark/benchmark.sh']);
});
test('RMS catalog and generated dropdown agree, preserving the custom path',()=>{
  const schema=parse(readFileSync(`${root}/terraform/stacks/discovery/schema.yaml`,'utf8'));
  const catalog=JSON.parse(readFileSync(`${root}/catalogs/models.json`));
  assert.deepEqual(schema.variables.model_choice.enum,['custom',...catalog.models.map(m=>m.id)]);
  assert.deepEqual(schema.variables.model.visible.eq,['${model_choice}','custom']);
  assert.equal(new Set(catalog.models.map(m=>m.id)).size,catalog.models.length);
});
test('released production-stack chart produces valid single-node pod structure',{skip:!process.env.HELM_CHART_FILE},()=>{
  const directory=mkdtempSync(`${tmpdir()}/oke-helm-test-`);
  try {
    writeFileSync(`${directory}/values.json`,JSON.stringify(render(base).helm_values));
    const yaml=execFileSync('helm',['template','fixture',process.env.HELM_CHART_FILE,'-f',`${directory}/values.json`],{encoding:'utf8'});
    const documents=parseAllDocuments(yaml).map(document=>{assert.equal(document.errors.length,0);return document.toJSON();}).filter(Boolean);
    const deployment=documents.find(d=>d.kind==='Deployment'&&d.spec.template.metadata.labels['oke-llm/model']==='fixture');
    assert.ok(deployment);checkPod(deployment.spec.template);
    assert.equal(deployment.spec.strategy.type,'Recreate');
    assert.ok(deployment.spec.template.spec.containers[0].args.includes(base.model_revision));
  } finally {rmSync(directory,{recursive:true,force:true});}
});
test('deployment RMS form includes every Terraform handoff variable',()=>{
  const schema=parse(readFileSync(`${root}/terraform/stacks/deployment/schema.yaml`,'utf8'));
  const variables=[...readFileSync(`${root}/terraform/stacks/deployment/variables.tf`,'utf8').matchAll(/variable "([^"]+)"/g)].map(m=>m[1]).sort();
  assert.deepEqual(Object.keys(schema.variables).sort(),variables);
});

test('RMS scope filters use optional list controls with typed items',()=>{
  const schema=parse(readFileSync(`${root}/terraform/stacks/discovery/schema.yaml`,'utf8'));
  for(const name of ['regions','shape_names']) {
    assert.equal(schema.variables[name].required,false);
    assert.equal(schema.variables[name].type,'list');
    assert.equal(schema.variables[name].default,'[]');
    const item=schema.variables[schema.variables[name].valueType];
    assert.ok(item);assert.equal(item.visible,false);
  }
});

test('RMS groups reference defined variable names and bootstrap region is selectable',()=>{
  for(const stack of ['discovery','deployment']) {
    const schema=parse(readFileSync(`${root}/terraform/stacks/${stack}/schema.yaml`,'utf8'));
    for(const group of schema.variableGroups) for(const name of group.variables) {
      assert.match(name,/^[A-Za-z_][A-Za-z0-9_]*$/);
      assert.ok(Object.hasOwn(schema.variables,name),`Undefined RMS field ${stack}:${name}`);
    }
  }
  const schema=parse(readFileSync(`${root}/terraform/stacks/discovery/schema.yaml`,'utf8'));
  assert.equal(schema.variables.region.type,'oci:identity:region:name');
  assert.equal(schema.variables.region.default,'${session.region}');
  assert.notEqual(schema.variableGroups.find(g=>g.variables.includes('region')).visible,false);
});
