// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync,cpSync,copyFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {parseAllDocuments,parse,stringify} from 'yaml';
const root=resolve(import.meta.dirname,'..'), modulePath=`${root}/modules/llm-deployment/model-delivery`;
const hash=s=>createHash('sha256').update(s).digest('hex');
const image=`docker.io/vllm/vllm-openai@sha256:${'e'.repeat(64)}`;
const defaults={MODEL_NAMESPACE:'fixture-model-test',MODEL_ID:'org/model',MODEL_REVISION:'a'.repeat(40),SERVING_IMAGE:image,VLLM_USE_RUST_FRONTEND:'0',TP:'2',PP:'1',HOSTS_PER_REPLICA:'1',GPUS_PER_POD:'2',REPLICAS:'2',CONTEXT_LENGTH:'4096',CONCURRENCY:'8',INFERENCE_PROBE:'none'};
const config={namespace:defaults.MODEL_NAMESPACE,release:'model',identity:'model-fixture',ownership_token:'stable-owned-model-token',timeout_seconds:600,defaults,router_enabled:true,
 platform:{platform_name:'fixture',cluster_id:'cluster',allocation:{gpu_pool_id:'pool'},node_count:1,gpu_count_per_host:4,gpu_selector:'oke-llm/allocation=fixture',required_components:['lws'],transport:{requires_rdma:false}},
 storage:{mode:'direct_hf',pvc_name:'',snapshot_bytes:1024,workspace_gib:8,workspace_explicit:false},autoscaling:{enabled:false},model:{selection:{serving_configuration:{recipe:{args:[],env:{}}}}}};
const mock=String.raw`
const fs=require('node:fs'),path=require('node:path'),a=process.argv.slice(2),tool=path.basename(process.argv[1]);
const file=process.env.MOCK_STATE,s=JSON.parse(fs.readFileSync(file)),out=v=>process.stdout.write(typeof v==='string'?v:JSON.stringify(v));
s.calls.push({tool,args:a});fs.writeFileSync(file,JSON.stringify(s));
if(tool==='kubectl'){
 if(a.includes('namespace'))out(s.namespace);
 else if(a.includes('nodes'))out({items:s.nodes});
 else if(a.includes('pvc'))out(s.pvc||{});
 else if(a.includes('configmap'))out(a.includes('kube-system')?s.context||{}:s.owner||{});
 else if(a.includes('crd'))out({status:{conditions:[{type:'Established',status:'True'}]}});
 else if(a.includes('pods'))out({items:s.pods});
 else if(a.includes('deployment'))out(s.controller||{metadata:{generation:1},spec:{replicas:1},status:{observedGeneration:1,availableReplicas:1,conditions:[{type:'Available',status:'True'}]}});
 else if(a.includes('port-forward')){setInterval(()=>{},10000);process.on('SIGTERM',()=>process.exit(0));}
 else if(a.includes('wait')||a.includes('rollout')){if(s.notReady)process.exit(1);}
 else{process.stderr.write('Unexpected kubectl');process.exit(1);}
} else if(tool==='oci'){
 if(a.slice(0,3).join(' ')==='ce node-pool list')out({data:s.pools||[s.pool]});
 else if(a.slice(0,3).join(' ')==='ce node-pool get')out({data:s.pool});
 else process.exit(1);
} else if(tool==='helm'){
 if(a[0]==='status')out({version:s.revision||3,info:{status:'deployed'}});
 else if(a.slice(0,2).join(' ')==='get metadata')out({chart:'oke-llm-model',version:'0.1.0-test',revision:s.metadataRevision||s.revision||3,status:'deployed'});
 else process.exit(1);
} else if(tool==='curl'){
 if(s.healthFailure&&a.at(-1).endsWith('/health'))process.exit(22);
 else if(a.at(-1).endsWith('/v1/models'))out({data:[{id:s.advertisedModel||'org/model'}]});
 else if(a.at(-1).includes('/v1/'))out({choices:[{text:'ready'}]});
} else if(tool!=='sleep') process.exit(1);
`;
function fixture(changes={}){
 const dir=mkdtempSync(`${tmpdir()}/model-runtime-`);mkdirSync(`${dir}/runtime`);mkdirSync(`${dir}/bin`);
 for(const file of ['common.sh','preflight.sh','validate.sh','benchmark.sh'])copyFileSync(`${modulePath}/scripts/${file}`,`${dir}/runtime/${file}`);
 for(const tool of ['kubectl','helm','curl','sleep','oci'])writeFileSync(`${dir}/bin/${tool}`,`#!${process.execPath}\n${mock}`,{mode:0o755});
 const current=structuredClone(config);if(changes.config)Object.assign(current,changes.config);
 writeFileSync(`${dir}/runtime/config.json`,JSON.stringify(current));
 const namespace={metadata:{labels:{'oke-llm/platform-owner':hash('fixture/cluster').slice(0,32),'oke-llm/model-namespace':'true'},annotations:{'oke-llm/platform-name':'fixture','oke-llm/cluster-id':'cluster'}}};
 const pod={metadata:{},spec:{containers:[{name:'vllm',image}]},status:{conditions:[{type:'Ready',status:'True'}]}};
 const env={...process.env,PATH:`${dir}/bin:${process.env.PATH}`,...defaults,CHART_VERSION:'0.1.0-test',DELIVERY_GENERATION:'generation',MOCK_STATE:`${dir}/state.json`,...changes.env};
 const settings=hash(`${JSON.stringify(Object.fromEntries([...Object.keys(current.defaults).filter(k=>k!=='INFERENCE_PROBE').sort(),'CHART_VERSION'].map(k=>[k,env[k]])))}\n`);
 const state={calls:[],namespace,nodes:[{status:{conditions:[{type:'Ready',status:'True'}],allocatable:{'nvidia.com/gpu':'4','ephemeral-storage':'200Gi'}}}],pods:[pod,pod],owner:{data:{ownership_token:current.ownership_token,generation:'generation',status:'ready',settings_sha256:settings,helm_revision:'3',chart_version:'0.1.0-test'}},...changes.state};
 writeFileSync(`${dir}/state.json`,JSON.stringify(state));
 return{dir,env,run(code){const r=spawnSync('bash',['-c',`set -euo pipefail; source runtime/common.sh; ${code}`],{cwd:dir,env,encoding:'utf8',timeout:15000});return{...r,state:JSON.parse(readFileSync(`${dir}/state.json`))};},close(){rmSync(dir,{recursive:true,force:true});}};
}
test('unassessed KV-aware routing is rejected before contacting the cluster',()=>{
 const f=fixture({config:{routing_mode:'kvaware',lmcache:{enabled:true,mode:'inprocess'}}});
 try{const r=f.run('model_inputs');assert.equal(r.status,2,r.stderr);assert.match(r.stderr,/KV-aware routing.*unavailable/);assert.deepEqual(r.state.calls,[]);}finally{f.close();}
});
test('in-process cache without compatibility evidence cannot bypass validation',()=>{
 const f=fixture({config:{lmcache:{enabled:true,mode:'inprocess'}}});
 try{const r=f.run('model_inputs');assert.equal(r.status,2,r.stderr);assert.match(r.stderr,/In-process LMCache is unavailable/);assert.deepEqual(r.state.calls,[]);}finally{f.close();}
});
test('cached model or image pipeline overrides require compatibility reassessment',()=>{
 for(const env of [{MODEL_ID:'org/other'},{SERVING_IMAGE:`docker.io/vllm/vllm-openai@sha256:${'f'.repeat(64)}`}]){
  const f=fixture({config:{lmcache:{enabled:true,mode:'mp'}},env});
  try{const r=f.run('model_inputs');assert.equal(r.status,2,r.stderr);assert.match(r.stderr,/requires a stack Apply to reassess compatibility/);assert.deepEqual(r.state.calls,[]);}finally{f.close();}
 }
});
test('model preflight accepts packed retained GPU slots and rejects missing allocation before native Helm',()=>{
 for(const [changes,expected] of [[{},0],[{config:{platform:{...config.platform,allocation:{gpu_pool_id:null}}}},2],[{env:{REPLICAS:'3'}},2],[{env:{TP:'1'}},2],[{env:{MODEL_NAMESPACE:'other'}},2],[{state:{nodes:[]}},2]]){
  const f=fixture(changes);try{const r=f.run('model_inputs; model_geometry; model_storage');assert.equal(r.status,expected,r.stderr);assert(!r.state.calls.some(c=>['create','apply','replace'].some(v=>c.args.includes(v))));}finally{f.close();}
 }
});
test('model namespace ownership, immutable images and unknown disk estimates fail closed',()=>{
 for(const changes of [{state:{namespace:{metadata:{labels:{},annotations:{}}}}},{env:{SERVING_IMAGE:'vllm/vllm-openai:latest'}},{config:{storage:{...config.storage,snapshot_bytes:null,workspace_explicit:false}}},{config:{storage:{...config.storage,mode:'staged_object_storage'}}}]){
  const f=fixture(changes);try{const r=f.run('model_inputs; model_storage');assert.notEqual(r.status,0,r.stderr);}finally{f.close();}
 }
 const explicit=fixture({config:{storage:{...config.storage,snapshot_bytes:null,workspace_explicit:true}}});try{assert.equal(explicit.run('model_inputs; model_storage').status,0);}finally{explicit.close();}
});
test('manual image parameters require an explicit registry before any cluster operation',()=>{
 const digest='e'.repeat(64);
 for(const reference of [`vllm/vllm-openai@sha256:${digest}`,`engine@sha256:${digest}`]){
  const f=fixture({env:{SERVING_IMAGE:reference}});try{const r=f.run('model_inputs');assert.equal(r.status,2,r.stderr);assert.match(r.stderr,/must include its registry/);assert.equal(r.state.calls.length,0);}finally{f.close();}
 }
 for(const registry of ['docker.io','ghcr.io','fra.ocir.io','localhost','localhost:5000','registry.example:5443']){
  const f=fixture({env:{SERVING_IMAGE:`${registry}/org/engine@sha256:${digest}`}});try{const r=f.run('model_inputs');assert.equal(r.status,0,r.stderr);}finally{f.close();}
 }
});
test('frontend parameters accept only Python0 or explicit Rust1 before any cluster action',()=>{
 for(const frontend of ['0','1','true','2','python','']){
  const f=fixture({env:{VLLM_USE_RUST_FRONTEND:frontend}});try{const r=f.run('model_inputs');if(['0','1'].includes(frontend))assert.equal(r.status,0,r.stderr);else{assert.equal(r.status,2,r.stderr);assert.match(r.stderr,/VLLM_USE_RUST_FRONTEND must be 0/);assert.equal(r.state.calls.length,0);}}finally{f.close();}
 }
});
test('main revision is accepted only for direct Hub serving and reported as mutable',()=>{
 const f=fixture({env:{MODEL_REVISION:'main'}});
 try{const r=f.run('model_inputs; model_validate');assert.equal(r.status,0,r.stderr);const report=JSON.parse(readFileSync(`${f.dir}/model-validation.json`));assert.equal(report.model_revision,'main');assert.equal(report.model_revision_kind,'mutable_ref');assert.equal(report.image,image);}finally{f.close();}
 for(const mode of ['existing_pvc','staged_object_storage']){
  const f=fixture({env:{MODEL_REVISION:'main'},config:{storage:{...config.storage,mode,pvc_name:'retained-weights'}}});try{const r=f.run('model_inputs');assert.equal(r.status,2,r.stderr);assert.match(r.stderr,/retained PVC and staged snapshots require an immutable commit/);assert.equal(r.state.calls.length,0);}finally{f.close();}
 }
 for(const revision of ['latest','refs/heads/main','MAIN','abc123','main;touch unwanted']){
  const f=fixture({env:{MODEL_REVISION:revision}});try{const r=f.run('model_inputs');assert.equal(r.status,2,r.stderr);assert.match(r.stderr,/40-character Hugging Face commit or exactly main/);assert.equal(r.state.calls.length,0);}finally{f.close();}
 }
});
test('independent operations require matching settings, current Helm revision and generation',()=>{
 const f=fixture();try{assert.equal(f.run('model_inputs; model_ready_owner').status,0);}finally{f.close();}
 for(const changes of [{state:{revision:4}},{state:{metadataRevision:4}},{state:{owner:{data:{ownership_token:config.ownership_token,generation:'old',status:'ready'}}}}]){
  const f=fixture(changes);try{assert.notEqual(f.run('model_ready_owner').status,0);}finally{f.close();}
 }
 const f2=fixture();try{f2.env.CONTEXT_LENGTH='8192';assert.notEqual(f2.run('model_ready_owner').status,0);}finally{f2.close();}
});
test('health/model identity validation makes no text-inference claim for arbitrary modalities',()=>{
 const f=fixture();try{const r=f.run('model_inputs; model_validate');assert.equal(r.status,0,r.stderr);const result=JSON.parse(readFileSync(`${f.dir}/model-validation.json`));assert.match(result.inference_probe,/not_run/);assert.equal(result.responses_conversation_persistence,false);assert.equal(result.model_revision,defaults.MODEL_REVISION);assert.equal(result.model_revision_kind,'immutable_commit');assert(!r.state.calls.some(c=>c.args.includes('--data-binary')));}finally{f.close();}
 const wrong=fixture({state:{advertisedModel:'other'}});try{assert.notEqual(wrong.run('model_validate').status,0);}finally{wrong.close();}
});
const values={identity:'model-fixture',model:'org/model',revision:'a'.repeat(40),image,tensorParallel:'2',pipelineParallel:'1',hosts:'1',gpusPerPod:'2',replicas:'2',contextLength:'4096',concurrency:'8',recipeArgs:['--tool-call-parser','qwen3_coder','--reasoning-parser','qwen3','--kv-cache-dtype','fp8','--dtype','bfloat16'],recipeEnv:{VLLM_USE_RUST_FRONTEND:'1'},nodeSelector:{'oke-llm/allocation':'fixture'},cpu:'2',memory:'16Gi',shm:'8Gi',workspace:'32Gi',hfTokenSecret:'hf-token',pvcName:'',modelPath:'',rdmaResource:'',router:{enabled:false},monitoring:{enabled:false},autoscaling:{enabled:false}};
function chartFixture(full=false){const dir=mkdtempSync(`${tmpdir()}/model-chart-`);cpSync(`${modulePath}/chart`,dir,{recursive:true});const metadata={apiVersion:'v2',name:'oke-llm-model',version:'0.1.0-test'};if(full){metadata.dependencies=[{name:'vllm-stack',version:'0.1.14',repository:'https://vllm-project.github.io/production-stack',condition:'router.enabled'}];mkdirSync(`${dir}/charts`);copyFileSync(process.env.MODEL_ROUTER_CHART_FILE,`${dir}/charts/vllm-stack-0.1.14.tgz`);}writeFileSync(`${dir}/Chart.yaml`,stringify(metadata));return{dir,render(overrides={}){writeFileSync(`${dir}/test-values.yaml`,stringify({...values,...overrides}));return parseAllDocuments(execFileSync('helm',['template','model',dir,'--namespace','fixture-model-test','-f',`${dir}/test-values.yaml`],{encoding:'utf8',maxBuffer:16*1024*1024})).map(d=>{assert.equal(d.errors.length,0);return d.toJSON();}).filter(Boolean);},close(){rmSync(dir,{recursive:true,force:true});}};}
test('single-host chart preserves recipe flags and packs replicas without universal anti-affinity',()=>{
 const c=chartFixture();try{const docs=c.render(),d=docs.find(d=>d.kind==='Deployment'),pod=d.spec.template.spec,args=pod.containers[0].args;assert.equal(d.spec.replicas,2);assert.deepEqual(d.spec.strategy,{type:'RollingUpdate',rollingUpdate:{maxSurge:0,maxUnavailable:1}});assert.equal(pod.affinity,undefined);assert.deepEqual(args.slice(1,1+values.recipeArgs.length),values.recipeArgs);assert.equal(args[args.indexOf('--dtype')+1],'bfloat16');assert.equal(args[args.indexOf('--kv-cache-dtype')+1],'fp8');assert.deepEqual(pod.nodeSelector,values.nodeSelector);assert.equal(pod.containers[0].resources.requests['nvidia.com/gpu'],2);assert.equal(d.spec.template.metadata.labels['oke-llm/endpoint'],'true');assert(!docs.some(d=>d.kind==='PersistentVolumeClaim'||d.kind==='CustomResourceDefinition'||d.kind==='ScaledObject'));}finally{c.close();}
});
test('LWS chart has rank variables, per-group host separation and leader-only endpoints',()=>{
 const c=chartFixture();try{const docs=c.render({hosts:'2',pipelineParallel:'2',rdmaResource:'rdma/resource'}),lws=docs.find(d=>d.kind==='LeaderWorkerSet'),t=lws.spec.leaderWorkerTemplate;assert.equal(t.size,2);assert.equal(t.leaderTemplate.metadata.labels['oke-llm/endpoint'],'true');assert.equal(t.workerTemplate.metadata.labels['oke-llm/endpoint'],'false');for(const p of[t.leaderTemplate,t.workerTemplate]){assert.deepEqual(p.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].matchLabelKeys,['leaderworkerset.sigs.k8s.io/group-index']);assert(p.spec.containers[0].args.includes('$(LWS_LEADER_ADDRESS)'));assert.equal(p.spec.containers[0].resources.requests['rdma/resource'],1);}assert(t.workerTemplate.spec.containers[0].args.includes('--headless'));assert(!t.leaderTemplate.spec.containers[0].args.includes('--headless'));}finally{c.close();}
});
test('multi-host HTTP service cannot shadow the LWS discovery service',()=>{
 const c=chartFixture();try{
  for(const hosts of ['1','2']){
   const docs=c.render({hosts}),http=docs.find(d=>d.kind==='Service');
   assert.equal(http.metadata.name,hosts==='1'?'model':'model-http');
   assert.equal(http.spec.type,'ClusterIP');
   assert.equal(http.spec.publishNotReadyAddresses,undefined);
   assert.equal(http.spec.selector['oke-llm/endpoint'],'true');
   if(hosts==='2')assert.notEqual(http.metadata.name,docs.find(d=>d.kind==='LeaderWorkerSet').metadata.name);
  }
 }finally{c.close();}
});
test('validation selects the effective direct HTTP service or the router',()=>{
 for(const [hosts,router,endpoint] of [['1',false,'model'],['2',false,'model-http'],['2',true,'model-router-service']]){
  const f=fixture({config:{router_enabled:router},env:{HOSTS_PER_REPLICA:hosts,PP:hosts,REPLICAS:'1'}});
  try{const r=f.run('model_inputs; model_validate');assert.equal(r.status,0,r.stderr);assert(r.state.calls.some(c=>c.tool==='kubectl'&&c.args.includes('port-forward')&&c.args.includes('service/'+endpoint)));}finally{f.close();}
 }
});
test('benchmark Jobs select the effective direct HTTP service or router',()=>{
 for(const [hosts,router,endpoint] of [['1',false,'model'],['2',false,'model-http'],['2',true,'model-router-service']]){
  const f=fixture({config:{router_enabled:router,serving:{recipe:{args:[]}},benchmark_image:image},env:{HOSTS_PER_REPLICA:hosts,PP:hosts,OCI_DEPLOYMENT_ID:'deployment',BENCHMARK_BACKEND:'openai',BENCHMARK_REQUESTS:'2',BENCHMARK_INPUT_TOKENS:'256',BENCHMARK_OUTPUT_TOKENS:'64'}});
  try{
   writeFileSync(`${f.dir}/runtime/bench-client.sh`,'exit 0\n');
   writeFileSync(`${f.dir}/bin/kubectl`,`#!${process.execPath}\nconst a=process.argv.slice(2);if(a.includes('wait'))process.exit(1);if(a.includes('apply'))process.stdin.resume();else if(a.includes('create'))console.log('{}');\n`,{mode:0o755});
   const r=f.run('bash runtime/benchmark.sh');assert.equal(r.status,2,r.stderr);
   const job=JSON.parse(readFileSync(`${f.dir}/benchmark-job.json`));
   assert.equal(job.spec.template.spec.containers[0].env.find(e=>e.name==='BASE_URL').value,`http://${endpoint}.fixture-model-test.svc:${router?'80':'8000'}`);
  }finally{f.close();}
 }
});
test('pinned upstream router dependency renders only namespaced router resources and literal leader selector',{skip:!process.env.MODEL_ROUTER_CHART_FILE},()=>{
 const c=chartFixture(true);try{const docs=c.render({router:{enabled:true},'vllm-stack':{servingEngineSpec:{enableEngine:false,modelSpec:[]},routerSpec:{enableRouter:true,serviceAccountName:'oke-llm-router',routingLogic:'prefixaware',extraArgs:['--k8s-label-selector','oke-llm/model=model-fixture,oke-llm/endpoint=true'],repository:'lmcache/lmstack-router',tag:'v0.1.14@sha256:'+'7'.repeat(64)},'kube-prometheus-stack':{enabled:false},'prometheus-adapter':{enabled:false},'k8s-aibom':{enabled:false}}});const router=docs.find(d=>d.kind==='Deployment'&&d.metadata.name==='model-deployment-router');assert(router);const container=router.spec.template.spec.containers[0];assert(container.args.includes('prefixaware'));assert(container.args.includes('oke-llm/model=model-fixture,oke-llm/endpoint=true'));assert.equal(router.spec.template.spec.serviceAccountName,'oke-llm-router');assert(!docs.some(d=>['ClusterRole','ClusterRoleBinding','CustomResourceDefinition','Role','RoleBinding','PersistentVolumeClaim'].includes(d.kind)));}finally{c.close();}
});
test('model RMS form selects existing cluster/pool and matches Terraform variables without GPU allocation fields',()=>{
 const schema=parse(readFileSync(`${root}/templates/llm-deployment/schema.yaml`,'utf8')),variables=[...readFileSync(`${root}/templates/llm-deployment/variables.tf`,'utf8').matchAll(/variable "([^"]+)"/g)].map(m=>m[1]);assert.deepEqual(Object.keys(schema.variables).filter(key=>!Object.values(schema.variables).some(v=>v.valueType===key)).sort(),variables.sort());for(const key of['discovery_json','gpu_shape','gpu_image_id','node_count','platform_binding'])assert.equal(schema.variables[key],undefined);assert.equal(schema.variables.cluster_id.required,true);assert.equal(schema.variables.cluster_id.type,'oci:container:cluster:id');assert.equal(schema.variables.gpu_pool_id.type,'string');for(const group of schema.variableGroups)for(const key of group.variables)assert(Object.hasOwn(schema.variables,key));
});
test('all model Shell sources parse',()=>{for(const file of ['common.sh','preflight.sh','validate.sh','benchmark.sh','bench-client.sh','operation.sh'])execFileSync('bash',['-n',`${modulePath}/scripts/${file}`]);});

test('model operation preserves primary failures when lock release or log reporting also fails',()=>{
 for(const [code,releaseFails,reportFails] of [[0,false,false],[23,false,false],[23,true,false],[0,true,false],[23,false,true],[0,false,true]]){
  const f=fixture({env:{OCI_DEPLOYMENT_ID:'deployment',DELIVERY_OPERATION:'validate'}});
  try{
   copyFileSync(`${modulePath}/scripts/operation.sh`,`${f.dir}/runtime/operation.sh`);
   writeFileSync(`${f.dir}/runtime/common.sh`,'namespace=model; release=model; cluster=cluster; owner=owner; timeout=10\nmodel_inputs(){ :; }\nmodel_geometry(){ :; }\nmodel_platform_ready(){ :; }\nmodel_ready_owner(){ :; }\n');
   writeFileSync(`${f.dir}/runtime/tools.sh`,'delivery_tools(){ :; }\n');
   writeFileSync(`${f.dir}/runtime/lock.sh`,`lock_acquire(){ lock_held=true; }\nlock_release(){ touch lock-release-called; return ${releaseFails?37:0}; }\n`);
   writeFileSync(`${f.dir}/runtime/validate.sh`,`exit ${code}\n`);
   if(reportFails)writeFileSync(`${f.dir}/bin/jq`,'#!/bin/sh\nexit 29\n',{mode:0o755});
   const r=f.run('bash runtime/operation.sh');
   const expected=code||((releaseFails||reportFails)?1:0);
   assert.equal(r.status,expected,r.stderr);
   assert.equal(readFileSync(`${f.dir}/lock-release-called`).length,0,'always attempt lock release, including failed reporting');
   if(!reportFails){
    assert.match(r.stdout,/Model operation result:/);
    const report=JSON.parse(readFileSync(`${f.dir}/operation-result.json`));
    assert.equal(report.exit_code,expected);assert.equal(report.status,expected===0?'ready':'failed');
   }
   assert.equal(r.state.calls.length,0,'routine status must not call OCI');
  }finally{f.close();}
 }
});

test('independent validation prints its evidence without uploading a routine artifact',()=>{
 const f=fixture({config:{platform:{...config.platform,required_components:[],components:{}}}});
 try{const r=f.run('bash runtime/validate.sh');assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/Model validation result:/);assert.match(r.stdout,/shared_controller_checks/);assert(!r.state.calls.some(c=>c.tool==='oci'));}finally{f.close();}
});

test('failed benchmark Job prints its logs without requiring a failure artifact upload',()=>{
 const f=fixture({config:{serving:{recipe:{args:[]}},benchmark_image:image},env:{OCI_DEPLOYMENT_ID:'deployment',BENCHMARK_BACKEND:'openai',BENCHMARK_REQUESTS:'32',BENCHMARK_INPUT_TOKENS:'256',BENCHMARK_OUTPUT_TOKENS:'64'}});
 try{
  writeFileSync(`${f.dir}/bin/kubectl`,`#!${process.execPath}\nconst a=process.argv.slice(2);if(a.includes('wait'))process.exit(1);if(a.includes('logs'))console.log('fixture benchmark Job failure');if(a.includes('apply'))process.stdin.resume();else if(a.includes('create'))console.log('{}');\n`,{mode:0o755});
  const r=f.run('bash runtime/benchmark.sh');assert.equal(r.status,2,r.stderr);assert.match(r.stderr,/fixture benchmark Job failure/);assert.match(r.stderr,/deployment log/);assert(!r.state.calls.some(c=>c.tool==='oci'));
 }finally{f.close();}
});

test('successful benchmark keeps downloadable native JSON results and prints them in the deployment log',()=>{
 const f=fixture({config:{serving:{recipe:{args:[]}},benchmark_image:image},env:{OCI_DEPLOYMENT_ID:'deployment',DELIVERY_RESULT_REPOSITORY:'benchmark-results',BENCHMARK_BACKEND:'openai',BENCHMARK_REQUESTS:'32',BENCHMARK_INPUT_TOKENS:'256',BENCHMARK_OUTPUT_TOKENS:'64'}});
 try{
  writeFileSync(`${f.dir}/bin/kubectl`,`#!${process.execPath}\nconst a=process.argv.slice(2);if(a.includes('logs'))console.log('BENCHMARK_RESULT_BEGIN\\n{"completed":32}\\nBENCHMARK_RESULT_END');if(a.includes('apply'))process.stdin.resume();else if(a.includes('create'))console.log('{}');\n`,{mode:0o755});
  writeFileSync(`${f.dir}/bin/oci`,`#!${process.execPath}\nconst fs=require('node:fs'),a=process.argv.slice(2);if(a.slice(0,4).join(' ')!=='artifacts generic artifact upload-by-path')process.exit(99);fs.writeFileSync('benchmark-export.json',JSON.stringify({repository:a[a.indexOf('--repository-id')+1],path:a[a.indexOf('--artifact-path')+1],result:JSON.parse(fs.readFileSync(a[a.indexOf('--content-body')+1]))}));\n`,{mode:0o755});
  const r=f.run('bash runtime/benchmark.sh');assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/vLLM benchmark result:/);const exported=JSON.parse(readFileSync(`${f.dir}/benchmark-export.json`));assert.equal(exported.repository,'benchmark-results');assert.match(exported.path,/vllm-benchmark.json$/);assert.equal(exported.result.completed,32);
 }finally{f.close();}
});

test('a permanent health failure cannot be hidden by a successful model identity response',()=>{
 const f=fixture({state:{healthFailure:true}});try{const r=f.run('model_validate');assert.notEqual(r.status,0);assert.match(r.stderr,/never passed \/health/);assert(!r.state.calls.some(c=>c.tool==='curl'&&c.args.at(-1).endsWith('/v1/models')));}finally{f.close();}
});
test('multi-host model PVCs require shared read access and cannot reuse CPU staging scratch',()=>{
 const storage={...config.storage,mode:'existing_pvc',pvc_name:'weights'},pvc={metadata:{annotations:{'oke-llm/model-revision':defaults.MODEL_REVISION}},spec:{accessModes:['ReadWriteOnce']},status:{phase:'Bound'}};
 const f=fixture({config:{storage,platform:{...config.platform,node_count:2}},state:{pvc}});try{const r=f.run('model_storage');assert.notEqual(r.status,0);assert.match(r.stderr,/ROX\/RWX/);}finally{f.close();}
 const rwx=fixture({config:{storage,platform:{...config.platform,node_count:2}},state:{pvc:{...pvc,spec:{accessModes:['ReadWriteMany']}}}});try{assert.equal(rwx.run('model_storage').status,0);}finally{rwx.close();}
 const scratch=fixture({config:{storage,platform:{...config.platform,model_storage:{scratch_pvc:'weights'}}},state:{pvc}});try{const r=scratch.run('model_storage');assert.notEqual(r.status,0);assert.match(r.stderr,/CPU staging scratch/);}finally{scratch.close();}
});

test('PVC access checks use the actual retained pool size even when the stable model config only needs one host',()=>{
 const storage={...config.storage,mode:'existing_pvc',pvc_name:'weights'},pvc={metadata:{annotations:{'oke-llm/model-revision':defaults.MODEL_REVISION}},spec:{accessModes:['ReadWriteOnce']},status:{phase:'Bound'}};
 for(const pool of [{'node-config-details':{size:2},nodes:[{}]},{'node-config-details':{size:1},nodes:[{},{}]}]){
  const f=fixture({config:{storage,platform:{...config.platform,node_count:1}},state:{pvc}});
  try{writeFileSync(`${f.dir}/model-pool.json`,JSON.stringify({data:pool}));const r=f.run('model_storage');assert.equal(r.status,2,r.stderr);assert.match(r.stderr,/ROX\/RWX/);}finally{f.close();}
 }
});
test('shared controller readiness uses exact bound generations and read-only controller checks',()=>{
 const component={mode:'managed',namespace:'lws-system',owner_name:'owned-controller',generation:'generation',deployment_names:['lws-controller-manager']},platform={...config.platform,components:{lws:component}};
 const f=fixture({config:{platform}});try{const r=f.run('model_platform_ready');assert.equal(r.status,0,r.stderr);assert(r.state.calls.every(c=>c.tool==='kubectl'&&c.args.includes('get')));}finally{f.close();}
 for(const state of [{owner:{data:{generation:'old',status:'ready'}}},{controller:{metadata:{generation:2},spec:{replicas:1},status:{observedGeneration:1,availableReplicas:1,conditions:[{type:'Available',status:'True'}]}}}]){
  const f=fixture({config:{platform},state});try{assert.notEqual(f.run('model_platform_ready').status,0);}finally{f.close();}
 }
 const reuse=fixture({config:{platform:{...platform,components:{lws:{...component,mode:'reuse'}}}}});try{const r=reuse.run('model_platform_ready');assert.equal(r.status,0,r.stderr);assert(!r.state.calls.some(c=>c.args.includes('configmap')));}finally{reuse.close();}
});
test('model ServiceMonitor carries the infrastructure selector and scaling targets whole retained replicas',()=>{
 const c=chartFixture();try{const docs=c.render({monitoring:{enabled:true,platform:'fixture'},autoscaling:{enabled:true,min_replicas:1,max_replicas:2,target_inflight:8,prometheus_url:'http://prometheus'}});const monitor=docs.find(d=>d.kind==='ServiceMonitor'),scaler=docs.find(d=>d.kind==='ScaledObject');assert.equal(monitor.metadata.labels['oke-llm/platform'],'fixture');assert.equal(scaler.spec.maxReplicaCount,2);assert.equal(scaler.spec.scaleTargetRef.kind,'Deployment');assert(scaler.spec.triggers[0].metadata.query.includes('namespace="fixture-model-test"'));}finally{c.close();}
});
test('benchmark parameter validation rejects shell expressions and oversized token contexts before any Job',()=>{
 for(const env of [{BENCHMARK_REQUESTS:'$(touch unwanted)'},{BENCHMARK_INPUT_TOKENS:'4096'}]){
  const f=fixture({config:{serving:{recipe:{args:[]}}},env:{BENCHMARK_BACKEND:'openai',BENCHMARK_REQUESTS:'32',BENCHMARK_INPUT_TOKENS:'256',BENCHMARK_OUTPUT_TOKENS:'64',...env}});try{const r=f.run('bash runtime/benchmark.sh');assert.notEqual(r.status,0,r.stderr);assert(!r.state.calls.some(c=>c.args.includes('create')));}finally{f.close();}
 }
});

const runtimePlatform={...config.platform,binding_mode:'runtime',project_id:'ocid1.devopsproject.oc1.model',cluster_compartment_id:'cluster-compartment',gpu_pool_compartment_id:'pool-compartment',gpu_shape:'BM.GPU.A10.4',availability_domain:'AD-1'};
const runtimePool={id:'pool','cluster-id':'cluster','lifecycle-state':'ACTIVE','node-shape':'BM.GPU.A10.4','initial-node-labels':[{key:'oke-llm/allocation',value:'fixture'}],'freeform-tags':{'oke-llm-allocation':'owned-allocation'},'node-config-details':{'placement-configs':[{'availability-domain':'AD-1'}]},nodes:[{id:'instance','lifecycle-state':'ACTIVE'}]};
const runtimeNode={metadata:{labels:{}},spec:{providerID:'oci://instance'},status:{conditions:[{type:'Ready',status:'True'}],allocatable:{'nvidia.com/gpu':'4','ephemeral-storage':'200Gi'}}};
test('runtime discovers an exact owned OCI pool and never equates allocatable GPU totals with free devices',()=>{
 const otherAdPool={...runtimePool,'node-config-details':{'placement-configs':[{'availability-domain':'AD-2'}]}};
 const f=fixture({config:{platform:{...runtimePlatform,allocation:{gpu_pool_id:null}}},state:{pool:otherAdPool,nodes:[runtimeNode]}});
 try{const r=f.run('model_geometry');assert.equal(r.status,0,r.stderr);const evidence=JSON.parse(readFileSync(`${f.dir}/model-allocation-check.json`));assert.equal(evidence.free_gpu_headroom,'unknown_other_namespace_requests_not_visible');assert.deepEqual(evidence.actual_availability_domains,['AD-2']);assert.equal(evidence.retained_pool_requires_new_regional_capacity,false);assert(!r.state.calls.some(c=>c.tool==='kubectl'&&(c.args.includes('--all-namespaces')||c.args.includes('-A'))));assert(r.state.calls.some(c=>c.tool==='oci'&&c.args.includes('list')));}finally{f.close();}
});
test('runtime pool resolution rejects missing/ambiguous, foreign, unready and shared GPU allocations',()=>{
 const cases=[
  {pools:[]}, {pools:[runtimePool,runtimePool]},
  {pool:{...runtimePool,'cluster-id':'foreign'}},
  {pool:{...runtimePool,'node-shape':'foreign'}},
  {pool:{...runtimePool,'lifecycle-state':'UPDATING'}},
  {pool:{...runtimePool,'initial-node-labels':[]}}, {pool:{...runtimePool,'freeform-tags':{}}},
  {pool:{...runtimePool,nodes:[{id:'foreign-instance','lifecycle-state':'ACTIVE'}]}},
  {nodes:[{...runtimeNode,spec:{providerID:'oci://foreign-instance'}}]},
  {nodes:[{...runtimeNode,metadata:{labels:{'nvidia.com/gpu.replicas':'4'}}}]},
  {nodes:[{...runtimeNode,spec:{...runtimeNode.spec,unschedulable:true}}]}
 ];
 for(const change of cases){const f=fixture({config:{platform:{...runtimePlatform,allocation:{gpu_pool_id:null}}},state:{pool:runtimePool,nodes:[runtimeNode],...change}});try{const r=f.run('model_geometry');assert.notEqual(r.status,0,JSON.stringify(change));assert(!r.state.calls.some(c=>c.args.some(a=>['create','update','delete','apply','replace'].includes(a))));}finally{f.close();}}
});
function runtimeContext(component){const metadata={labels:{'oke-llm/platform-owner':hash('fixture/cluster').slice(0,32)},annotations:{'oke-llm/model-namespace':defaults.MODEL_NAMESPACE,'oke-llm/model-project-id':runtimePlatform.project_id}};return{metadata,data:{'context.json':JSON.stringify({platform_name:'fixture',cluster_id:'cluster',model_project_id:runtimePlatform.project_id,model_namespace:defaults.MODEL_NAMESPACE,gpu_pool_id:'runtime',components:{lws:component}})}};}
test('runtime obtains live controller generations only through the trusted fixed read context',()=>{
 const component={mode:'managed',namespace:'lws-system',owner_name:'owned-controller',ownership_token:hash('fixture/cluster/lws'),release_name:'lws',crd_names:['leaderworkersets.leaderworkerset.x-k8s.io'],deployment_names:['lws-controller-manager']};
 const owner={data:{ownership_token:component.ownership_token,generation:'current-not-frozen',status:'ready',chart_version:'0.8.0',helm_revision:'3'}};
 const controller={metadata:{generation:2,annotations:{'meta.helm.sh/release-name':'lws','meta.helm.sh/release-namespace':'lws-system'}},spec:{replicas:1},status:{observedGeneration:2,availableReplicas:1,conditions:[{type:'Available',status:'True'}]}};
 for(const [change,pass] of [[{},true],[{owner:{data:{...owner.data,status:'prepared'}}},false],[{owner:{data:{...owner.data,ownership_token:'foreign'}}},false],[{controller:{...controller,metadata:{...controller.metadata,annotations:{'meta.helm.sh/release-name':'other'}}}},false],[{context:{metadata:{labels:{},annotations:{}},data:{}}},false]]){
  const f=fixture({config:{platform:runtimePlatform},state:{context:runtimeContext(component),owner,controller,...change}});try{const r=f.run('model_platform_ready');assert.equal(r.status===0,pass,r.stderr);if(pass){const evidence=JSON.parse(readFileSync(`${f.dir}/platform-readiness.json`));assert.equal(evidence[0].current_ready_generation,'current-not-frozen');assert(r.state.calls.every(c=>c.tool==='kubectl'&&c.args.includes('get')));}}finally{f.close();}
 }
});
test('bounded placement failure reports that free devices were not established at preflight',()=>{
 const f=fixture({state:{notReady:true}});try{const r=f.run('model_validate');assert.notEqual(r.status,0);assert.match(r.stderr,/not proof of free devices/);}finally{f.close();}
});

test('native chart refuses explicit Ray and disaggregated recipe strategies before hardware or chart actions',()=>{
 for(const model of [{selection:{platform_plan:{topology:{backend:'ray',strategy:'multi_node_tp_pp'}}}},{selection:{platform_plan:{topology:{backend:'mp',strategy:'disaggregated_requires_adapter'}}}}]){
  const f=fixture({config:{model}});try{const r=f.run('bash runtime/preflight.sh');assert.notEqual(r.status,0);assert.match(r.stderr,/native multiprocessing only/);assert(!r.state.calls.some(c=>c.tool==='oci'||c.tool==='curl'));}finally{f.close();}
 }
 const f=fixture({config:{serving:{recipe:{args:['--distributed-executor-backend=ray']}}}});try{const r=f.run('bash runtime/preflight.sh');assert.notEqual(r.status,0);assert.match(r.stderr,/native multiprocessing only/);}finally{f.close();}
});

test('RDMA reuse requires one actual AD, the actual Compute Cluster and advertised device resources',()=>{
 const transport={requires_rdma:true,rdma_resource_name:'rdma/test'};
 const platform={...runtimePlatform,transport,allocation:{gpu_pool_id:'pool',compute_cluster_id:'compute-cluster'}};
 const pool={...runtimePool,'node-config-details':{'placement-configs':[{'availability-domain':'AD-2'}],'compute-cluster-id':'compute-cluster'}};
 const node={...runtimeNode,status:{...runtimeNode.status,allocatable:{...runtimeNode.status.allocatable,'rdma/test':'1'}}};
 for(const [change,pass] of [[{},true],[{pool:{...pool,'node-config-details':{...pool['node-config-details'],'compute-cluster-id':'foreign'}}},false],[{pool:{...pool,'node-config-details':{...pool['node-config-details'],'placement-configs':[{'availability-domain':'AD-1'},{'availability-domain':'AD-2'}]}}},false],[{nodes:[runtimeNode]},false]]){
  const f=fixture({config:{platform},state:{pool,nodes:[node],...change}});try{const r=f.run('model_geometry');assert.equal(r.status===0,pass,r.stderr);}finally{f.close();}
 }
});
test('editable runtime arguments cannot retarget the model project, cluster, platform or pool boundary',()=>{
 const fixed={MODEL_PROJECT_ID:runtimePlatform.project_id,MODEL_CLUSTER_ID:'cluster',MODEL_PLATFORM_NAME:'fixture',MODEL_GPU_POOL_ID:'runtime'};
 for(const key of Object.keys(fixed)){
  const f=fixture({config:{platform:runtimePlatform,defaults:{...defaults,...fixed}},env:{...fixed,[key]:'other'}});try{const r=f.run('model_inputs');assert.notEqual(r.status,0);assert.match(r.stderr,/immutable onboarding boundary/);assert.equal(r.state.calls.length,0);}finally{f.close();}
 }
});

const workspaceNode=(quantity,name='gpu')=>({metadata:{name},status:{conditions:[{type:'Ready',status:'True'}],allocatable:{'nvidia.com/gpu':'4',...(quantity===undefined?{}:{'ephemeral-storage':quantity})}}});
const largeSnapshotStorage={...config.storage,snapshot_bytes:51.75*1024**3,workspace_gib:104,workspace_explicit:true};
test('direct Hub workspace rejects the real unexpanded GPU root filesystem before native Helm',()=>{
 const f=fixture({config:{storage:largeSnapshotStorage},state:{nodes:[workspaceNode('28447447403')]},env:{TP:'4',GPUS_PER_POD:'4',REPLICAS:'1'}});
 try{
  const r=f.run('model_inputs; model_geometry; model_storage; echo NATIVE_HELM_MAY_START');
  assert.equal(r.status,2,r.stderr);assert.match(r.stderr,/104Gi/);assert.match(r.stderr,/grow its root partition\/filesystem \(oci-growfs\)/);assert.match(r.stderr,/boot-volume size alone/);assert.doesNotMatch(r.stdout,/NATIVE_HELM_MAY_START/);
  const check=JSON.parse(readFileSync(`${f.dir}/model-workspace-check.json`));
  assert.equal(check.workspace_bytes,104*1024**3);assert.equal(check.nodes[0].allocatable_bytes,28447447403);assert.equal(check.eligible_hosts,0);assert.equal(check.maximum_pod_slots,0);assert.equal(check.possible,false);
  assert.equal(r.state.calls.filter(c=>c.tool==='kubectl'&&c.args.includes('nodes')).length,1);
  assert(!r.state.calls.some(c=>c.tool==='helm'||c.args.includes('--all-namespaces')||c.args.includes('-A')));
 }finally{f.close();}
});
test('direct Hub workspace parses Kubernetes bytes, binary, decimal, milli and exponent quantities',()=>{
 const quantities=[214748364800,'214748364800','200Gi','204800Mi','209715200Ki','214748364.8k','214748.3648M','214.7483648G','0.2147483648T','214748364800000m','2.147483648e11','2.147483648E+11','+214748364800','200.Gi','0.1953125Ti'];
 for(const quantity of quantities){
  const f=fixture({config:{storage:largeSnapshotStorage},state:{nodes:[workspaceNode(quantity)]},env:{TP:'4',GPUS_PER_POD:'4',REPLICAS:'1'}});
  try{const r=f.run('model_geometry');assert.equal(r.status,0,`${quantity}: ${r.stderr}`);const check=JSON.parse(readFileSync(`${f.dir}/model-workspace-check.json`));assert.equal(check.nodes[0].allocatable_bytes,214748364800);assert.equal(check.maximum_pod_slots,1);assert.equal(check.possible,true);assert.match(check.free_ephemeral_headroom,/unknown/);}finally{f.close();}
 }
});
test('direct Hub workspace enforces the exact per-Pod byte boundary',()=>{
 for(const [quantity,pass] of [[String(104*1024**3),true],[String(104*1024**3-1),false]]){
  const f=fixture({config:{storage:largeSnapshotStorage},state:{nodes:[workspaceNode(quantity)]},env:{TP:'4',GPUS_PER_POD:'4',REPLICAS:'1'}});
  try{const r=f.run('model_geometry');assert.equal(r.status===0,pass,r.stderr);}finally{f.close();}
 }
});
test('direct Hub workspace fails actionably for missing or unknown node quantities',()=>{
 for(const quantity of [undefined,null,'','26 GB','not-a-quantity','-1','1e999',{},true]){
  const f=fixture({config:{storage:largeSnapshotStorage},state:{nodes:[workspaceNode(quantity)]},env:{TP:'4',GPUS_PER_POD:'4',REPLICAS:'1'}});
  try{const r=f.run('model_geometry');assert.equal(r.status,2,`${quantity}: ${r.stderr}`);assert.match(r.stderr,/ephemeral-storage is missing\/unrecognized/);const check=JSON.parse(readFileSync(`${f.dir}/model-workspace-check.json`));assert.deepEqual(check.unknown_quantity_nodes,['gpu']);assert.equal(check.possible,false);}finally{f.close();}
 }
});
test('direct Hub workspace ceilings account for packed replicas and distinct multi-host placements',()=>{
 const cases=[
  {quantities:['28447447403','190Gi'],workspace:68,env:{REPLICAS:'2'},hosts:1,slots:2,pass:true},
  {quantities:['28447447403','190Gi'],workspace:68,env:{REPLICAS:'1',HOSTS_PER_REPLICA:'2',PP:'2'},hosts:1,slots:2,pass:false},
  {quantities:['104Gi','104Gi'],workspace:104,env:{REPLICAS:'3',GPUS_PER_POD:'1',TP:'1'},hosts:2,slots:2,pass:false},
  {quantities:['190Gi','190Gi'],workspace:68,env:{REPLICAS:'2',HOSTS_PER_REPLICA:'2',PP:'2'},hosts:2,slots:4,pass:true}
 ];
 for(const c of cases){
  const f=fixture({config:{platform:{...config.platform,node_count:2,kubernetes_version:'v1.34.1'},storage:{...largeSnapshotStorage,workspace_gib:c.workspace}},state:{nodes:c.quantities.map((q,i)=>workspaceNode(q,`gpu-${i}`))},env:c.env});
  try{const r=f.run('model_inputs; model_geometry');assert.equal(r.status===0,c.pass,r.stderr);const check=JSON.parse(readFileSync(`${f.dir}/model-workspace-check.json`));assert.equal(check.eligible_hosts,c.hosts);assert.equal(check.maximum_pod_slots,c.slots);assert.equal(check.possible,c.pass);assert(!r.state.calls.some(call=>call.args.includes('--all-namespaces')||call.args.includes('-A')));}finally{f.close();}
 }
});
test('direct Hub workspace ceiling uses the already validated autoscaling maximum',()=>{
 for(const [maximum,pass] of [['2',true],['3',false]]){
  const f=fixture({config:{storage:{...largeSnapshotStorage,workspace_gib:68},autoscaling:{enabled:true}},state:{nodes:[workspaceNode('190Gi')]},env:{TP:'1',GPUS_PER_POD:'1',REPLICAS:'1',MIN_REPLICAS:'1',MAX_REPLICAS:maximum,TARGET_INFLIGHT:'8',PROMETHEUS_URL:'http://prometheus'}});
  try{const r=f.run('model_inputs; model_geometry');assert.equal(r.status===0,pass,r.stderr);const check=JSON.parse(readFileSync(`${f.dir}/model-workspace-check.json`));assert.equal(check.replicas_at_ceiling,Number(maximum));assert.equal(check.required_pod_slots,Number(maximum));}finally{f.close();}
 }
});
test('non-direct model storage keeps its existing placement checks without a new ephemeral requirement',()=>{
 const f=fixture({config:{storage:{...config.storage,mode:'existing_pvc',pvc_name:'weights'}},state:{nodes:[workspaceNode(undefined)]}});
 try{const r=f.run('model_geometry');assert.equal(r.status,0,r.stderr);assert.doesNotMatch(r.stdout,/workspace_gib|allocatable_quantity/);}finally{f.close();}
});

test('cache readiness requires the deployed launcher and reports store/retrieve as unverified',()=>{
 const pod={metadata:{},spec:{containers:[{name:'vllm',image,command:['bash','/lmcache/launch.sh']}]},status:{conditions:[{type:'Ready',status:'True'}]}};
 const f=fixture({config:{lmcache:{enabled:true,mode:'mp'},routing_mode:'prefixaware'},state:{pods:[pod,pod]}});
 try{const r=f.run('model_inputs; model_validate');assert.equal(r.status,0,r.stderr);const result=JSON.parse(readFileSync(`${f.dir}/model-validation.json`));assert.equal(result.lmcache.store_retrieve_validation,'manual_cache_benchmark_required');assert.equal(result.routing,'prefixaware');}finally{f.close();}
 const missing=fixture({config:{lmcache:{enabled:true,mode:'mp'}}});try{const r=missing.run('model_inputs; model_validate');assert.equal(r.status,2,r.stderr);assert.match(r.stderr,/LMCache launcher is absent/);}finally{missing.close();}
});
