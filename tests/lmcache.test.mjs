// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync, execFileSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,readFileSync,cpSync,mkdirSync,copyFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
import {parseAllDocuments,stringify} from 'yaml';
const modulePath=resolve(import.meta.dirname,'../modules/llm-deployment/model-delivery');
const launcher=`${modulePath}/chart/files/lmcache-launch.sh`;
function runtime(mode,cacheCode=7,modelCode=9){
 const dir=mkdtempSync(`${tmpdir()}/lmcache-launch-`);
 writeFileSync(`${dir}/python3`,'#!/bin/bash\ncat >/dev/null\nif [[ ${STARTUP_FAIL:-0} == 1 && $2 =~ ^[0-9]+$ ]]; then sleep 0.4; exit 1; fi\nexit "${IMPORT_CODE:-0}"\n',{mode:0o755});
 writeFileSync(`${dir}/lmcache`,'#!/bin/bash\nprintf "%s\\n" "$@" > "$CAPTURE/cache"\ntrap \'echo stopped >> "$CAPTURE/cache"; exit 0\' TERM\nif [[ $CACHE_CODE == hold ]]; then while :; do sleep 0.1; done; else sleep 0.2; exit "$CACHE_CODE"; fi\n',{mode:0o755});
 writeFileSync(`${dir}/vllm`,'#!/bin/bash\nprintf "%s\\n" "$@" > "$CAPTURE/model"\ntrap \'echo stopped >> "$CAPTURE/model"; exit 0\' TERM\nif [[ $MODEL_CODE == hold ]]; then while :; do sleep 0.1; done; else exit "$MODEL_CODE"; fi\n',{mode:0o755});
 return {dir,run(extra={}){return spawnSync('bash',[launcher,'org/model','--kv-transfer-config','{"literal":"$value"}'],{encoding:'utf8',timeout:5000,env:{...process.env,PATH:`${dir}:${process.env.PATH}`,CAPTURE:dir,LMCACHE_ADAPTER:mode,LMCACHE_CPU_MEMORY_GB:'8',LMCACHE_CHUNK_SIZE:'256',CACHE_CODE:String(cacheCode),MODEL_CODE:String(modelCode),...extra}});},close(){rmSync(dir,{recursive:true,force:true});}};
}
test('MP companion failure stops inference and preserves its failure status',()=>{
 const f=runtime('mp',7,'hold');try{const r=f.run();assert.equal(r.status,7,r.stderr);assert.match(readFileSync(`${f.dir}/model`,'utf8'),/stopped/);assert.match(readFileSync(`${f.dir}/cache`,'utf8'),/--host\n127.0.0.1/);}finally{f.close();}
});
test('inference failure stops cache process and preserves arguments literally',()=>{
 const f=runtime('mp','hold',9);try{const r=f.run();assert.equal(r.status,9,r.stderr);assert.match(readFileSync(`${f.dir}/cache`,'utf8'),/stopped/);assert.match(readFileSync(`${f.dir}/model`,'utf8'),/\{"literal":"\$value"\}/);}finally{f.close();}
});
test('missing connector fails before starting cache or model; inprocess starts only inference',()=>{
 const f=runtime('inprocess',7,9);try{assert.equal(f.run({IMPORT_CODE:'6'}).status,6);assert.equal(f.run().status,9);assert.throws(()=>readFileSync(`${f.dir}/cache`));}finally{f.close();}
});
const values={identity:'fixture',model:'org/model',revision:'a'.repeat(40),image:`docker.io/vllm/vllm-openai@sha256:${'e'.repeat(64)}`,tensorParallel:'2',pipelineParallel:'1',hosts:'1',gpusPerPod:'2',replicas:'2',contextLength:'4096',concurrency:'4',recipeArgs:[],recipeEnv:{LMCACHE_CHUNK_SIZE:'256'},nodeSelector:{'oke-llm/allocation':'fixture'},cpu:'2',memory:'28Gi',shm:'8Gi',workspace:'32Gi',hfTokenSecret:'',pvcName:'',modelPath:'',rdmaResource:'',router:{enabled:false},monitoring:{enabled:false},autoscaling:{enabled:false},lmcache:{enabled:true,mode:'mp',cpu_memory_gb:8,chunk_size:256,controller:false}};
function render(v){const dir=mkdtempSync(`${tmpdir()}/lmcache-chart-`);try{cpSync(`${modulePath}/chart`,dir,{recursive:true});const metadata={apiVersion:'v2',name:'oke-llm-model',version:'0.1.0-test'};if(v['vllm-stack']){metadata.dependencies=[{name:'vllm-stack',version:'0.1.14',repository:'https://vllm-project.github.io/production-stack',condition:'router.enabled'}];mkdirSync(`${dir}/charts`);copyFileSync(process.env.MODEL_ROUTER_CHART_FILE,`${dir}/charts/vllm-stack-0.1.14.tgz`);}writeFileSync(`${dir}/Chart.yaml`,stringify(metadata));writeFileSync(`${dir}/test-values.yaml`,stringify(v));return parseAllDocuments(execFileSync('helm',['template','model',dir,'-f',`${dir}/test-values.yaml`],{encoding:'utf8'})).map(d=>{assert.deepEqual(d.errors,[]);return d.toJSON();}).filter(Boolean);}finally{rmSync(dir,{recursive:true,force:true});}}
test('MP chart delivers readable launcher and keeps one GPU allocation per TP Pod',()=>{
 const docs=render(values),pod=docs.find(d=>d.kind==='Deployment').spec.template.spec,c=pod.containers[0];
 assert.equal(pod.containers.length,1);assert(docs.find(d=>d.kind==='Service').spec.ports.some(p=>p.name==='cache-metrics'&&p.port===9090));assert.deepEqual(c.command,['bash','/lmcache/launch.sh']);assert.equal(c.resources.requests['nvidia.com/gpu'],2);assert(c.volumeMounts.some(v=>v.name==='lmcache'));assert.match(docs.find(d=>d.kind==='ConfigMap').data['launch.sh'],/lmcache server --host 127.0.0.1/);
});
test('controller worker identities and addresses use Pod fields; disabled cache is unchanged',()=>{
 const v=structuredClone(values);v.lmcache.controller=true;v.lmcache.mode='inprocess';let docs=render(v),env=docs.find(d=>d.kind==='Deployment').spec.template.spec.containers[0].env;
 assert.equal(env.find(e=>e.name==='LMCACHE_LMCACHE_INSTANCE_ID').valueFrom.fieldRef.fieldPath,'metadata.name');assert.equal(env.find(e=>e.name==='LMCACHE_P2P_HOST').valueFrom.fieldRef.fieldPath,'status.podIP');
 v.lmcache.enabled=false;docs=render(v);assert(!docs.some(d=>d.kind==='ConfigMap'));assert.deepEqual(docs.find(d=>d.kind==='Deployment').spec.template.spec.containers[0].command,['vllm','serve']);
});

test('pinned router renders reachable controller reply and heartbeat service ports',{skip:!process.env.MODEL_ROUTER_CHART_FILE},()=>{
 const v=structuredClone(values);v.router.enabled=true;v.lmcache.mode='inprocess';v.lmcache.controller=true;
 v['vllm-stack']={servingEngineSpec:{enableEngine:false,modelSpec:[]},routerSpec:{enableRouter:true,routingLogic:'kvaware',repository:'docker.io/lmcache/lmstack-router',tag:'v0.1.14',lmcacheControllerPort:9000,lmcacheControllerReplyPort:9001,lmcacheControllerHeartbeatPort:9002,extraArgs:['--k8s-label-selector','oke-llm/model=fixture,oke-llm/endpoint=true'],extraPorts:[{name:'cache-reply',port:9001,targetPort:9001,protocol:'TCP'},{name:'cache-heartbeat',port:9002,targetPort:9002,protocol:'TCP'}]},cacheserverSpec:{enabled:false},loraController:{enableLoraController:false},sharedPvcStorage:{enabled:false},grafanaDashboards:{enabled:false},'kube-prometheus-stack':{enabled:false},'prometheus-adapter':{enabled:false},'k8s-aibom':{enabled:false}};
 const docs=render(v),service=docs.find(d=>d.kind==='Service'&&d.metadata.name.endsWith('-router-service')),router=docs.find(d=>d.kind==='Deployment'&&d.metadata.name.endsWith('-deployment-router'));
 const container=router.spec.template.spec.containers[0];
 assert.equal(container.env.find(e=>e.name==='PYTHONHASHSEED').value,'123');
 for(const [flag,port] of [['--lmcache-controller-port','9000'],['--lmcache-controller-reply-port','9001'],['--lmcache-controller-heartbeat-port','9002']])assert.equal(container.args[container.args.indexOf(flag)+1],port);
 assert.equal(docs.find(d=>d.kind==='Deployment'&&d.metadata.name==='model').spec.replicas,2);
 assert(service.spec.ports.some(p=>p.port===9000));assert(service.spec.ports.some(p=>p.port===9001&&p.targetPort===9001));assert(service.spec.ports.some(p=>p.port===9002&&p.targetPort===9002));assert(router.spec.template.spec.containers[0].args.includes('kvaware'));assert(!docs.some(d=>d.kind==='CustomResourceDefinition'));assert.equal(docs.filter(d=>d.kind==='Deployment').length,2);
 v.router.enabled=false;v.lmcache.enabled=false;assert.equal(render(v).filter(d=>d.kind==='Deployment').length,1);
});

test('cache startup failure preserves the server exit status before inference starts',()=>{
 const f=runtime('mp',17,'hold');try{const r=f.run({STARTUP_FAIL:'1'});assert.equal(r.status,17,r.stderr);assert.throws(()=>readFileSync(`${f.dir}/model`));assert.match(r.stderr,/LMCache startup failed \(status 17\)/);}finally{f.close();}
});
