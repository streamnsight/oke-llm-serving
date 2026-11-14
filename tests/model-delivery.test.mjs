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
const image=`vllm/vllm-openai@sha256:${'e'.repeat(64)}`;
const defaults={MODEL_NAMESPACE:'fixture-model-test',MODEL_ID:'org/model',MODEL_REVISION:'a'.repeat(40),SERVING_IMAGE:image,TP:'2',PP:'1',HOSTS_PER_REPLICA:'1',GPUS_PER_POD:'2',REPLICAS:'2',CONTEXT_LENGTH:'4096',CONCURRENCY:'8',INFERENCE_PROBE:'none'};
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
 else if(a.includes('configmap'))out(s.owner||{});
 else if(a.includes('crd'))out({status:{conditions:[{type:'Established',status:'True'}]}});
 else if(a.includes('pods'))out({items:s.pods});
 else if(a.includes('deployment'))out(s.controller||{metadata:{generation:1},spec:{replicas:1},status:{observedGeneration:1,availableReplicas:1,conditions:[{type:'Available',status:'True'}]}});
 else if(a.includes('port-forward')){setInterval(()=>{},10000);process.on('SIGTERM',()=>process.exit(0));}
 else if(a.includes('wait')||a.includes('rollout')){if(s.notReady)process.exit(1);}
 else{process.stderr.write('Unexpected kubectl');process.exit(1);}
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
 for(const tool of ['kubectl','helm','curl','sleep'])writeFileSync(`${dir}/bin/${tool}`,`#!${process.execPath}\n${mock}`,{mode:0o755});
 const current=structuredClone(config);if(changes.config)Object.assign(current,changes.config);
 writeFileSync(`${dir}/runtime/config.json`,JSON.stringify(current));
 const namespace={metadata:{labels:{'oke-llm/platform-owner':hash('fixture/cluster').slice(0,32),'oke-llm/model-namespace':'true'},annotations:{'oke-llm/platform-name':'fixture','oke-llm/cluster-id':'cluster'}}};
 const pod={metadata:{},spec:{containers:[{name:'vllm',image}]},status:{conditions:[{type:'Ready',status:'True'}]}};
 const env={...process.env,PATH:`${dir}/bin:${process.env.PATH}`,...defaults,CHART_VERSION:'0.1.0-test',DELIVERY_GENERATION:'generation',MOCK_STATE:`${dir}/state.json`,...changes.env};
 const settings=hash(`${JSON.stringify(Object.fromEntries([...Object.keys(current.defaults).filter(k=>k!=='INFERENCE_PROBE').sort(),'CHART_VERSION'].map(k=>[k,env[k]])))}\n`);
 const state={calls:[],namespace,nodes:[{status:{conditions:[{type:'Ready',status:'True'}],allocatable:{'nvidia.com/gpu':'4'}}}],pods:[pod,pod],owner:{data:{ownership_token:current.ownership_token,generation:'generation',status:'ready',settings_sha256:settings,helm_revision:'3',chart_version:'0.1.0-test'}},...changes.state};
 writeFileSync(`${dir}/state.json`,JSON.stringify(state));
 return{dir,env,run(code){const r=spawnSync('bash',['-c',`set -euo pipefail; source runtime/common.sh; ${code}`],{cwd:dir,env,encoding:'utf8',timeout:15000});return{...r,state:JSON.parse(readFileSync(`${dir}/state.json`))};},close(){rmSync(dir,{recursive:true,force:true});}};
}
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
test('independent operations require matching settings, current Helm revision and generation',()=>{
 const f=fixture();try{assert.equal(f.run('model_inputs; model_ready_owner').status,0);}finally{f.close();}
 for(const changes of [{state:{revision:4}},{state:{metadataRevision:4}},{state:{owner:{data:{ownership_token:config.ownership_token,generation:'old',status:'ready'}}}}]){
  const f=fixture(changes);try{assert.notEqual(f.run('model_ready_owner').status,0);}finally{f.close();}
 }
 const f2=fixture();try{f2.env.CONTEXT_LENGTH='8192';assert.notEqual(f2.run('model_ready_owner').status,0);}finally{f2.close();}
});
test('health/model identity validation makes no text-inference claim for arbitrary modalities',()=>{
 const f=fixture();try{const r=f.run('model_inputs; model_validate');assert.equal(r.status,0,r.stderr);const result=JSON.parse(readFileSync(`${f.dir}/model-validation.json`));assert.match(result.inference_probe,/not_run/);assert.equal(result.responses_conversation_persistence,false);assert(!r.state.calls.some(c=>c.args.includes('--data-binary')));}finally{f.close();}
 const wrong=fixture({state:{advertisedModel:'other'}});try{assert.notEqual(wrong.run('model_validate').status,0);}finally{wrong.close();}
});
const values={identity:'model-fixture',model:'org/model',revision:'a'.repeat(40),image,tensorParallel:'2',pipelineParallel:'1',hosts:'1',gpusPerPod:'2',replicas:'2',contextLength:'4096',concurrency:'8',recipeArgs:['--tool-call-parser','qwen3_coder','--reasoning-parser','qwen3','--kv-cache-dtype','fp8','--dtype','bfloat16'],recipeEnv:{VLLM_USE_RUST_FRONTEND:'1'},nodeSelector:{'oke-llm/allocation':'fixture'},cpu:'2',memory:'16Gi',shm:'8Gi',workspace:'32Gi',hfTokenSecret:'hf-token',pvcName:'',modelPath:'',rdmaResource:'',router:{enabled:false},monitoring:{enabled:false},autoscaling:{enabled:false}};
function chartFixture(full=false){const dir=mkdtempSync(`${tmpdir()}/model-chart-`);cpSync(`${modulePath}/chart`,dir,{recursive:true});const metadata={apiVersion:'v2',name:'oke-llm-model',version:'0.1.0-test'};if(full){metadata.dependencies=[{name:'vllm-stack',version:'0.1.14',repository:'https://vllm-project.github.io/production-stack',condition:'router.enabled'}];mkdirSync(`${dir}/charts`);copyFileSync(process.env.MODEL_ROUTER_CHART_FILE,`${dir}/charts/vllm-stack-0.1.14.tgz`);}writeFileSync(`${dir}/Chart.yaml`,stringify(metadata));return{dir,render(overrides={}){writeFileSync(`${dir}/test-values.yaml`,stringify({...values,...overrides}));return parseAllDocuments(execFileSync('helm',['template','model',dir,'--namespace','fixture-model-test','-f',`${dir}/test-values.yaml`],{encoding:'utf8',maxBuffer:16*1024*1024})).map(d=>{assert.equal(d.errors.length,0);return d.toJSON();}).filter(Boolean);},close(){rmSync(dir,{recursive:true,force:true});}};}
test('single-host chart preserves recipe flags and packs replicas without universal anti-affinity',()=>{
 const c=chartFixture();try{const docs=c.render(),d=docs.find(d=>d.kind==='Deployment'),pod=d.spec.template.spec,args=pod.containers[0].args;assert.equal(d.spec.replicas,2);assert.deepEqual(d.spec.strategy,{type:'RollingUpdate',rollingUpdate:{maxSurge:0,maxUnavailable:1}});assert.equal(pod.affinity,undefined);assert.deepEqual(args.slice(1,1+values.recipeArgs.length),values.recipeArgs);assert.equal(args[args.indexOf('--dtype')+1],'bfloat16');assert.equal(args[args.indexOf('--kv-cache-dtype')+1],'fp8');assert.deepEqual(pod.nodeSelector,values.nodeSelector);assert.equal(pod.containers[0].resources.requests['nvidia.com/gpu'],2);assert.equal(d.spec.template.metadata.labels['oke-llm/endpoint'],'true');assert(!docs.some(d=>d.kind==='PersistentVolumeClaim'||d.kind==='CustomResourceDefinition'));}finally{c.close();}
});
test('LWS chart has rank variables, per-group host separation and leader-only endpoints',()=>{
 const c=chartFixture();try{const docs=c.render({hosts:'2',pipelineParallel:'2',rdmaResource:'rdma/resource'}),lws=docs.find(d=>d.kind==='LeaderWorkerSet'),t=lws.spec.leaderWorkerTemplate;assert.equal(t.size,2);assert.equal(t.leaderTemplate.metadata.labels['oke-llm/endpoint'],'true');assert.equal(t.workerTemplate.metadata.labels['oke-llm/endpoint'],'false');for(const p of[t.leaderTemplate,t.workerTemplate]){assert.deepEqual(p.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].matchLabelKeys,['leaderworkerset.sigs.k8s.io/group-index']);assert(p.spec.containers[0].args.includes('$(LWS_LEADER_ADDRESS)'));assert.equal(p.spec.containers[0].resources.requests['rdma/resource'],1);}assert(t.workerTemplate.spec.containers[0].args.includes('--headless'));assert(!t.leaderTemplate.spec.containers[0].args.includes('--headless'));}finally{c.close();}
});
test('pinned upstream router dependency renders only namespaced router resources and literal leader selector',{skip:!process.env.MODEL_ROUTER_CHART_FILE},()=>{
 const c=chartFixture(true);try{const docs=c.render({router:{enabled:true},'vllm-stack':{servingEngineSpec:{enableEngine:false,modelSpec:[]},routerSpec:{enableRouter:true,serviceAccountName:'oke-llm-router',routingLogic:'prefixaware',extraArgs:['--k8s-label-selector','oke-llm/model=model-fixture,oke-llm/endpoint=true'],repository:'lmcache/lmstack-router',tag:'v0.1.14@sha256:'+'7'.repeat(64)},'kube-prometheus-stack':{enabled:false},'prometheus-adapter':{enabled:false},'k8s-aibom':{enabled:false}}});const router=docs.find(d=>d.kind==='Deployment'&&d.metadata.name==='model-deployment-router');assert(router);const container=router.spec.template.spec.containers[0];assert(container.args.includes('prefixaware'));assert(container.args.includes('oke-llm/model=model-fixture,oke-llm/endpoint=true'));assert.equal(router.spec.template.spec.serviceAccountName,'oke-llm-router');assert(!docs.some(d=>['ClusterRole','ClusterRoleBinding','CustomResourceDefinition','Role','RoleBinding','PersistentVolumeClaim'].includes(d.kind)));}finally{c.close();}
});
test('model RMS form matches typed Terraform fields and never asks for discovery JSON or GPU pool creation',()=>{
 const schema=parse(readFileSync(`${root}/templates/llm-deployment/schema.yaml`,'utf8')),variables=[...readFileSync(`${root}/templates/llm-deployment/variables.tf`,'utf8').matchAll(/variable "([^"]+)"/g)].map(m=>m[1]);assert.deepEqual(Object.keys(schema.variables).sort(),variables.sort());for(const key of['discovery_json','cluster_id','gpu_shape','gpu_image_id','node_count'])assert.equal(schema.variables[key],undefined);for(const group of schema.variableGroups)for(const key of group.variables)assert(Object.hasOwn(schema.variables,key));
});
test('all model Shell sources parse',()=>{for(const file of ['common.sh','preflight.sh','validate.sh','benchmark.sh','bench-client.sh','operation.sh'])execFileSync('bash',['-n',`${modulePath}/scripts/${file}`]);});

test('a permanent health failure cannot be hidden by a successful model identity response',()=>{
 const f=fixture({state:{healthFailure:true}});try{const r=f.run('model_validate');assert.notEqual(r.status,0);assert.match(r.stderr,/never passed \/health/);assert(!r.state.calls.some(c=>c.tool==='curl'&&c.args.at(-1).endsWith('/v1/models')));}finally{f.close();}
});
test('multi-host model PVCs require shared read access and cannot reuse CPU staging scratch',()=>{
 const storage={...config.storage,mode:'existing_pvc',pvc_name:'weights'},pvc={metadata:{annotations:{'oke-llm/model-revision':defaults.MODEL_REVISION}},spec:{accessModes:['ReadWriteOnce']},status:{phase:'Bound'}};
 const f=fixture({config:{storage,platform:{...config.platform,node_count:2}},state:{pvc}});try{const r=f.run('model_storage');assert.notEqual(r.status,0);assert.match(r.stderr,/ROX\/RWX/);}finally{f.close();}
 const rwx=fixture({config:{storage,platform:{...config.platform,node_count:2}},state:{pvc:{...pvc,spec:{accessModes:['ReadWriteMany']}}}});try{assert.equal(rwx.run('model_storage').status,0);}finally{rwx.close();}
 const scratch=fixture({config:{storage,platform:{...config.platform,model_storage:{scratch_pvc:'weights'}}},state:{pvc}});try{const r=scratch.run('model_storage');assert.notEqual(r.status,0);assert.match(r.stderr,/CPU staging scratch/);}finally{scratch.close();}
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
