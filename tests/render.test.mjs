// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { parseAllDocuments, parse } from 'yaml';
const root = resolve(import.meta.dirname, '..');
const engineImage = `vllm/vllm-openai@sha256:${"e".repeat(64)}`;
const components = JSON.parse(readFileSync(`${root}/modules/devops-serving/data/components.json`));
const base = { specification_hash:'b'.repeat(64),name:'fixture',namespace:'fixture',model:'org/model',model_revision:'a'.repeat(40),engine_image:engineImage,engine_version:'0.33.0',kv_dtype:'bfloat16',tensor_parallel_size:1,pipeline_parallel_size:1,replicas:1,context_length:4096,concurrency:4,requires_rdma:false,components,job_name:'fixture-test' };
const render = config => JSON.parse(execFileSync('jq', ['-f', `${root}/modules/devops-serving/scripts/render.jq`], { input:JSON.stringify(config), encoding:'utf8' }));
test('release packaging publishes only the entry discovery archive',()=>{
  const workflow=parse(readFileSync(`${root}/.github/workflows/package-stacks.yaml`,'utf8'));
  const uploads=workflow.jobs.package.steps.filter(s=>s.uses?.startsWith('actions/upload-artifact@'));
  assert.deepEqual(uploads.map(s=>s.with.path),['work/packages/oke-llm-discovery.zip']);
});
function checkPod(pod) {
  const spec = pod.spec;
  assert.equal(new Set((spec.volumes??[]).map(v=>v.name)).size, (spec.volumes??[]).length, 'duplicate volume names');
  for(const container of spec.containers) {
    assert.equal(new Set((container.volumeMounts??[]).map(v=>v.mountPath)).size,(container.volumeMounts??[]).length,'duplicate mount paths');
    assert.match(container.image, /@sha256:[a-f0-9]{64}$/);
  }
}
test('distributed groups have correct ranks, anti-affinity, RDMA requests and pinned images',()=>{
  const result=render({...base,pipeline_parallel_size:2,replicas:2,requires_rdma:true,rdma_resource_name:"nvidia.com/rdma_shared_device_a",rdma_network_attachment:"network-system/rdma-net"});
  assert.equal(result.helm_values.servingEngineSpec.enableEngine,false);
  const lws=result.multi_node_manifest.items[0];
  assert.equal(lws.spec.replicas,2); assert.equal(lws.spec.leaderWorkerTemplate.size,2);
  const leader=lws.spec.leaderWorkerTemplate.leaderTemplate, worker=lws.spec.leaderWorkerTemplate.workerTemplate;
  checkPod(leader);checkPod(worker);
  assert.ok(worker.spec.containers[0].args.includes('--headless'));
  assert.ok(worker.spec.containers[0].args.includes('$(LWS_WORKER_INDEX)'));
  assert.equal(leader.spec.containers[0].resources.requests['nvidia.com/rdma_shared_device_a'],1);
  assert.equal(leader.metadata.annotations['k8s.v1.cni.cncf.io/networks'],'network-system/rdma-net');
  assert.ok(leader.spec.tolerations.some(t=>t.key==='nvidia.com/gpu'));
  assert.ok(leader.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution.length);
  assert.equal(result.multi_node_manifest.items[2].spec.selector['leaderworkerset.sigs.k8s.io/group-index'],'1');
  assert.equal(result.helm_values.routerSpec.staticModels,'model,model');
  assert.equal(result.benchmark_job.spec.template.spec.containers[0].resources.requests['nvidia.com/gpu'],undefined);
  checkPod(result.benchmark_job.spec.template);
  assert.equal(result.rdma_manifest,undefined);
  assert.equal(components.gpu_operator,undefined);
  assert.equal(components.rdma_plugin_image,undefined);
  const benchmark=result.benchmark_job.spec.template.spec.containers[0];
  assert.match(benchmark.image,/^vllm\/vllm-openai-cpu@sha256:/);
  assert.deepEqual(benchmark.command,['bash','/benchmark/benchmark.sh']);
});
test('RMS takes a direct model ID without a static catalog selector',()=>{
  const schema=parse(readFileSync(`${root}/schema.yaml`,'utf8'));
  assert.equal(schema.variables.model.type,'string');
  assert.equal(schema.variables.model.required,true);
  assert.equal(schema.variables.model_choice,undefined);
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
    assert.ok(deployment.spec.template.spec.tolerations.some(t=>t.key==='nvidia.com/gpu'));
    assert.ok(deployment.spec.template.spec.containers[0].args.includes(base.model_revision));
  } finally {rmSync(directory,{recursive:true,force:true});}
});
test('deployment RMS form includes every Terraform handoff variable',()=>{
  const schema=parse(readFileSync(`${root}/templates/deployment/schema.yaml`,'utf8'));
  const variables=[...readFileSync(`${root}/templates/deployment/variables.tf`,'utf8').matchAll(/variable "([^"]+)"/g)].map(m=>m[1]).sort();
  const helpers=new Set(Object.values(schema.variables).map(v=>v.valueType).filter(Boolean));
  assert.deepEqual(Object.keys(schema.variables).filter(k=>!helpers.has(k)).sort(),variables);
});

test('RMS scope filters use optional list controls with typed items',()=>{
  const schema=parse(readFileSync(`${root}/schema.yaml`,'utf8'));
  for(const name of ['regions','shape_names']) {
    assert.equal(schema.variables[name].required,false);
    assert.equal(schema.variables[name].type,'list');
    assert.equal(schema.variables[name].default,'[]');
    const item=schema.variables[schema.variables[name].valueType];
    assert.ok(item);assert.equal(item.visible,false);
  }
});

test('RMS groups reference defined variable names and connection context is hidden',()=>{
  for(const stack of ['.','templates/deployment','templates/infrastructure']) {
    const schema=parse(readFileSync(`${root}/${stack}/schema.yaml`,'utf8'));
    for(const group of schema.variableGroups) for(const name of group.variables) {
      assert.match(name,/^[A-Za-z_][A-Za-z0-9_]*$/);
      assert.ok(Object.hasOwn(schema.variables,name),`Undefined RMS field ${stack}:${name}`);
    }
  }
  const schema=parse(readFileSync(`${root}/schema.yaml`,'utf8'));
  assert.equal(schema.variables.region.type,'string');
  assert.equal(schema.variables.region.default,'');
  assert.equal(schema.variables.region.visible,false);
  assert.equal(schema.variableGroups.find(g=>g.variables.includes('region')).visible,false);
});
test('infrastructure RMS form exposes GPU hardware without CPU-pool or model inputs',()=>{
  const schema=parse(readFileSync(`${root}/templates/infrastructure/schema.yaml`,'utf8'));
  const variables=[...readFileSync(`${root}/templates/infrastructure/variables.tf`,'utf8').matchAll(/variable "([^"]+)"/g)].map(m=>m[1]).sort();
  const helpers=new Set(Object.values(schema.variables).map(v=>v.valueType).filter(Boolean));
  assert.deepEqual(Object.keys(schema.variables).filter(k=>!helpers.has(k)).sort(),variables);
  for(const absent of ['model','discovery_json','engine_image','cpu_image_id','cpu_node_count']) assert.equal(schema.variables[absent],undefined);
  assert.equal(schema.variables.skip_gpu_allocation.default,false);
  assert.equal(schema.variables.provision_resources,undefined);
  for(const name of ['infrastructure_preview','platform','bootstrap_rbac','allocation']) assert.equal(schema.outputs[name].type,'json');
  assert.equal(schema.variables.compartment_id.default,'compartment_ocid');
  assert.equal(schema.variables.cluster_id.type,'oci:container:cluster:id');
  assert.equal(schema.variables.rdma_mode.default,'auto');
});
test('released LWS chart retains GPU exclusion and its default CPU budget',{skip:!process.env.LWS_CHART_FILE},()=>{
  const affinity={nodeAffinity:{requiredDuringSchedulingIgnoredDuringExecution:{nodeSelectorTerms:[{matchExpressions:[{key:'node.kubernetes.io/instance-type',operator:'In',values:['VM.Standard.E4.Flex']},{key:'nvidia.com/gpu',operator:'NotIn',values:['true']}]}]}}};
  const yaml=execFileSync('helm',['template','lws',process.env.LWS_CHART_FILE,'--include-crds','--set-json',`affinity=${JSON.stringify(affinity)}`],{encoding:'utf8',maxBuffer:16*1024*1024});
  const documents=parseAllDocuments(yaml).map(d=>{assert.equal(d.errors.length,0);return d.toJSON();}).filter(Boolean);
  const deployment=documents.find(d=>d.kind==='Deployment');
  assert.deepEqual(deployment.spec.template.spec.affinity,affinity);
  assert.equal(deployment.spec.template.spec.containers[0].resources.requests.cpu,1);
  assert.equal(deployment.spec.template.spec.containers[0].resources.requests.memory,'1Gi');
  assert.ok(documents.some(d=>d.kind==='CustomResourceDefinition'&&d.metadata.name==='leaderworkersets.leaderworkerset.x-k8s.io'));
});

test('frozen recipe argv and environment reach both Helm and distributed pods',()=>{
 const config={...base,serving_configuration:{recipe:{source_commit:'c'.repeat(40)}},engine_version:'0.33.0',engine_args:['--reasoning-parser','glm47','--enable-auto-tool-choice'],engine_env:{TEST_SETTING:'recipe-value'}};
 const single=render(config).helm_values.servingEngineSpec.modelSpec[0];
 assert.ok(single.args.includes('--reasoning-parser'));assert.ok(!single.args.includes('--default-chat-template-kwargs'));
 assert.deepEqual(single.env,[{name:'TEST_SETTING',value:'recipe-value'}]);
 if(process.env.HELM_CHART_FILE) {
  const dir=mkdtempSync(`${tmpdir()}/oke-recipe-chart-`);
  try {
   writeFileSync(`${dir}/values.json`,JSON.stringify(render(config).helm_values));
   const manifests=parseAllDocuments(execFileSync('helm',['template','fixture',process.env.HELM_CHART_FILE,'-f',`${dir}/values.json`],{encoding:'utf8'})).map(d=>d.toJSON()).filter(Boolean);
   const engine=manifests.find(m=>m.kind==='Deployment'&&m.spec.template.spec.containers.some(c=>c.name==='vllm')).spec.template.spec.containers.find(c=>c.name==='vllm');
   assert.ok(engine.args.includes('--reasoning-parser'));assert.ok(engine.env.some(e=>e.name==='TEST_SETTING'&&e.value==='recipe-value'));
  }finally{rmSync(dir,{recursive:true,force:true});}
 }

 const multi=render({...config,pipeline_parallel_size:2}).multi_node_manifest.items[0].spec.leaderWorkerTemplate;
 for(const pod of [multi.leaderTemplate,multi.workerTemplate]) {
  assert.ok(pod.spec.containers[0].args.includes('--reasoning-parser'));
  assert.ok(pod.spec.containers[0].env.some(e=>e.name==='TEST_SETTING'&&e.value==='recipe-value'));
 }
});

test('expert images preserve registry ports and explicit tags while pinning the digest',()=>{
 const image='registry.example:5000/org/engine:custom@sha256:'+'e'.repeat(64);
 const spec=render({...base,engine_image:image,engine_version:'0.33.0+custom'}).helm_values.servingEngineSpec.modelSpec[0];
 assert.equal(spec.repository,'registry.example:5000/org/engine');assert.equal(spec.tag,'custom@sha256:'+'e'.repeat(64));
 const untagged=render({...base,engine_image:'registry.example:5000/org/engine@sha256:'+'e'.repeat(64),engine_version:'0.33.0+custom'}).helm_values.servingEngineSpec.modelSpec[0];
 assert.equal(untagged.tag,'v0.33.0-custom@sha256:'+'e'.repeat(64));
});

test('discovery assesses requirements while deployment owns image and serving overrides',()=>{
 const discovery=parse(readFileSync(`${root}/schema.yaml`,'utf8'));
 const deployment=parse(readFileSync(`${root}/templates/deployment/schema.yaml`,'utf8'));
 for(const name of ['engine_channel','engine_version','engine_platform','recipe_features','kv_dtype','runtime_gib','margin'])assert.equal(discovery.variables[name],undefined,name+' must not be requested during discovery');
 for(const name of ['discovery_json','selection_id','engine_channel','engine_image','engine_version','engine_platform','recipe_features','engine_args','engine_env'])assert.ok(deployment.variables[name],name+' belongs in deployment');
});

test('deployment RMS uses dynamic target fields and hides routine infrastructure tuning',()=>{
 const schema=parse(readFileSync(`${root}/templates/deployment/schema.yaml`,'utf8'));
 assert.equal(schema.variables.compartment_id.type,'oci:identity:compartment:id');
 assert.equal(schema.variables.compartment_id.default,'compartment_ocid');
 assert.equal(schema.variables.cluster_id.type,'oci:container:cluster:id');
 assert.equal(schema.variables.cluster_id.dependsOn.compartmentId,'compartment_id');
 assert.equal(schema.variables.provision_resources.default,false);
 for(const name of ['gpu_image_id','cpu_image_id','subnet_id','cpu_subnet_id','devops_subnet_id','pod_subnet_id','cpu_node_count','rdma_resource_name','rdma_network_attachment']) {
  const group=schema.variableGroups.find(g=>g.variables.includes(name));
  assert.equal(group.visible,'advanced_settings',name);
  assert.equal(schema.variables[name].required,false,name);
 }
 for(const name of ['benchmark_requests','benchmark_input_tokens','benchmark_output_tokens']) assert.equal(schema.variables[name].visible,false);
 for(const name of ['subnet_id','cpu_subnet_id','devops_subnet_id','pod_subnet_id']) assert.equal(schema.variables[name].dependsOn.vcnId,'network_vcn_id');
});
