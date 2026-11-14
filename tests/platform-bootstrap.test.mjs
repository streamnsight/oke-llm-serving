// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..');
const modulePath=`${root}/modules/platform-bootstrap`;
const components=JSON.parse(readFileSync(`${modulePath}/data/components.json`));
const gpu={metadata:{name:'gpu',labels:{'node.kubernetes.io/instance-type':'BM.GPU.A10.4'}},spec:{},status:{conditions:[{type:'Ready',status:'True'}],allocatable:{'nvidia.com/gpu':'4'}}};
const cpu={metadata:{name:'existing-cpu',labels:{'node.kubernetes.io/instance-type':'VM.Standard.E4.Flex'}},spec:{},status:{conditions:[{type:'Ready',status:'True'}],allocatable:{cpu:'8',memory:'22Gi'}}};
const config={platform_name:'fixture',region:'us-ashburn-1',cluster_id:'cluster',node_count:1,gpu_count_per_host:4,requires_rdma:false,enable_lws:true,target:{kubernetes_version:'v1.34.1'},generation:'a'.repeat(64),evidence_bucket:'private-platform',storage_namespace:'fixture',evidence_prefix:'fixture/generation',components};
function readiness(changes={}) {
  return JSON.parse(execFileSync('jq',['-f',`${modulePath}/scripts/readiness.jq`],{input:JSON.stringify({config,gpu_nodes:{items:[gpu]},cpu_nodes:{items:[gpu,cpu]},...changes}),encoding:'utf8'}));
}
test('existing CPU nodes satisfy the controller requirement without allocation labels',()=>{
  const result=readiness(); assert.equal(result.ready,true); assert.equal(result.cpu_ready_nodes,1);
  assert.equal(readiness({cpu_nodes:{items:[gpu]}}).ready,false);
  assert.equal(readiness({cpu_nodes:{items:[{...cpu,spec:{unschedulable:true}}]}}).ready,false);
  assert.equal(readiness({cpu_nodes:{items:[{...cpu,spec:{taints:[{key:'reserved',effect:'NoSchedule'}]}}]}}).ready,false);
  assert.equal(readiness({config:{...config,enable_lws:false},cpu_nodes:{items:[]}}).ready,true);
});
test('platform readiness requires the full host GPU count and resolves RDMA explicitly',()=>{
  assert.equal(readiness({gpu_nodes:{items:[{...gpu,status:{...gpu.status,allocatable:{'nvidia.com/gpu':'2'}}}]}}).ready,false);
  const rdmaGpu={...gpu,status:{...gpu.status,allocatable:{...gpu.status.allocatable,'rdma/device':'1'}}};
  assert.equal(readiness({config:{...config,requires_rdma:true},gpu_nodes:{items:[rdmaGpu]}}).rdma_resource_name,'rdma/device');
  const ambiguous={...rdmaGpu,status:{...rdmaGpu.status,allocatable:{...rdmaGpu.status.allocatable,'rdma/second':'1'}}};
  assert.equal(readiness({config:{...config,requires_rdma:true},gpu_nodes:{items:[ambiguous]}}).fatal,true);
});
test('debug skips GPU and RDMA readiness while still requiring schedulable CPU capacity',()=>{
  const changes={config:{...config,gpu_allocation_enabled:false,requires_rdma:true},gpu_nodes:{items:[]},cpu_nodes:{items:[cpu]}};
  const result=readiness(changes);
  assert.equal(result.ready,true); assert.equal(result.validation_scope,'cpu_components_only'); assert.equal(result.gpu_validation,'skipped_debug');
  assert.equal(result.fatal,false); assert.deepEqual(result.reasons,[]);
  assert.equal(readiness({...changes,cpu_nodes:{items:[]}}).ready,false);
});

// Execute the real DAG/validator runner with external OCI/Kubernetes calls mocked.
const platformMock=String.raw`
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const dir=process.env.MOCK_DIR, tool=path.basename(process.argv[1]), a=process.argv.slice(2);
const state=JSON.parse(fs.readFileSync(dir+'/fixture.json'));
fs.appendFileSync(dir+'/calls.jsonl',JSON.stringify({tool,args:a})+'\n');
const arg=n=>a[a.indexOf(n)+1];
const out=x=>process.stdout.write(typeof x==='string'?x:JSON.stringify(x));
if(tool==='curl') {
 const url=a.find(x=>x.startsWith('https://'));let b;
 if(url.endsWith('/kubectl')) b=fs.readFileSync(dir+'/bin/kubectl');
 else if(url.endsWith('/kubectl.sha256')) b=crypto.createHash('sha256').update(fs.readFileSync(dir+'/bin/kubectl')).digest('hex');
 else if(url.endsWith('.sha256sum')) b=crypto.createHash('sha256').update(fs.readFileSync(dir+'/helm.tgz')).digest('hex');
 else b=fs.readFileSync(dir+'/helm.tgz');fs.writeFileSync(arg('-o'),b);
} else if(tool==='oci') {
 if(a[0]==='ce')fs.writeFileSync(arg('--file'),'mock kubeconfig');
 else if(a.slice(0,3).join(' ')==='devops deployment create-pipeline-deployment')out('ocid1.devopsdeployment.'+arg('--pipeline-id').split('.').at(-1));
 else if(a.slice(0,3).join(' ')==='devops deployment get')out(arg('--deployment-id').endsWith(state.failedChild||'---')?'FAILED':'SUCCEEDED');
 else if(a.slice(0,5).join(' ')==='artifacts generic artifact upload-by-path --repository-id') {
   if(state.failUpload)process.exit(1);
   fs.appendFileSync(dir+'/uploads.jsonl',JSON.stringify({path:arg('--artifact-path'),version:arg('--artifact-version'),body:JSON.parse(fs.readFileSync(arg('--content-body')))} )+'\n');
 } else throw Error('Unexpected OCI command '+a.join(' '));
} else if(tool==='kubectl') {
 if(a[0]==='get'&&a[1]==='configmap')out({data:{generation:'b'.repeat(64),status:state.staleOwner?'preparing':'ready',ownership_token:'fixture-owner',helm_revision:state.drift?'2':'3',chart_version:'1.0.0',deployment_id:'ocid1.devopsdeployment.previous'}});
 else if(a[0]==='get'&&a[1]==='nodes')out({items:a.includes('-l')?[]:[state.cpu]});
 else if(a[0]==='get'&&a[1]==='pvc')out({items:[{status:{phase:state.badPvc?'Pending':'Bound'}}]});
 else if(a[0]==='wait'||a[0]==='rollout') {if(state.failRollout)process.exit(1);}
 else throw Error('Unexpected Kubernetes mutation '+a.join(' '));
} else if(tool==='helm') {
 if(a[0]==='status')out({name:a[1],namespace:arg('--namespace'),version:3,info:{status:state.badRelease?'failed':'deployed'}});
 else if(a[0]==='get'&&a[1]==='metadata')out({name:a[2],namespace:arg('--namespace'),chart:a[2],version:state.chartDrift?'9.0.0':state.prefixedVersion?'v1.0.0':'1.0.0',revision:state.metadataChanged?4:3,status:'deployed'});
 else throw Error('Validator must not mutate Helm');
} else if(tool!=='sleep')throw Error('Unexpected tool');
`;
const platformComponent=(name,deps=[])=>({namespace:name,release_name:name,mode:'managed',owner_name:'owner-'+name,ownership_token:'fixture-owner',generation:'b'.repeat(64),pipeline_id:'ocid1.devopsdeploypipeline.'+name,dependency_keys:deps,crd_names:[],deployment_names:[name]});
function runPlatform(changes={},mode='validate',override={}) {
 const dir=mkdtempSync(`${tmpdir()}/oke-platform-graph-`);
 try {
  mkdirSync(dir+'/bin');mkdirSync(dir+'/linux-amd64');
  for(const tool of ['oci','helm','kubectl','curl','sleep'])writeFileSync(dir+'/bin/'+tool,`#!${process.execPath}\n${platformMock}`,{mode:0o755});
  writeFileSync(dir+'/linux-amd64/helm',readFileSync(dir+'/bin/helm'),{mode:0o755});
  execFileSync('tar',['-czf',dir+'/helm.tgz','-C',dir,'linux-amd64']);
  for(const file of ['platform.sh','readiness.jq'])writeFileSync(dir+'/'+file,readFileSync(`${modulePath}/scripts/${file}`));
  const c={...config,gpu_allocation_enabled:false,enable_lws:false,cpu_components_required:true,helm_version:components.helm_version,components:{a:platformComponent('a'),b:platformComponent('b',['a'])},...changes.config};
  writeFileSync(dir+'/platform.json',JSON.stringify(c));
  writeFileSync(dir+'/fixture.json',JSON.stringify({cpu,...changes}));
  const result=spawnSync('bash',[dir+'/platform.sh'],{env:{...process.env,MOCK_DIR:dir,PATH:dir+'/bin:'+process.env.PATH,PLATFORM_MODE:mode,REGION:c.region,CLUSTER_ID:c.cluster_id,PLATFORM_NAME:c.platform_name,RESULT_REPOSITORY_ID:'results',...override},encoding:'utf8',timeout:20000});
  const readLines=file=>{try{return readFileSync(dir+'/'+file,'utf8').trim().split('\n').filter(Boolean).map(JSON.parse);}catch{return [];}};
  return {...result,calls:readLines('calls.jsonl'),uploads:readLines('uploads.jsonl')};
 }finally{rmSync(dir,{recursive:true,force:true});}
}
test('fresh validation writes immutable Artifact Registry evidence and never deploys',()=>{
 const r=runPlatform();assert.equal(r.status,0,r.stderr);assert.equal(r.uploads.length,1);
 assert.equal(r.uploads[0].body.status,'ready');assert.match(r.uploads[0].version,/^[a-f0-9]{32}$/);
 assert.equal(r.uploads[0].body.node_checks.gpu_validation,'skipped_debug');
 assert.equal(r.uploads[0].body.components.a.chart_name,'a');assert.equal(r.uploads[0].body.components.a.chart_version,'1.0.0');
 assert(r.calls.some(c=>c.tool==='helm'&&c.args.slice(0,2).join(' ')==='get metadata'));
 assert.equal(r.calls.some(c=>c.args.includes('create-pipeline-deployment')),false);
 assert.equal(r.calls.some(c=>c.args.includes('os')),false);
});
test('DAG coordinator waits for prerequisites before starting dependent pipelines',()=>{
 const r=runPlatform({},'deploy');assert.equal(r.status,0,r.stderr);
 const starts=r.calls.filter(c=>c.args.includes('create-pipeline-deployment'));
 assert.deepEqual(starts.map(c=>c.args[c.args.indexOf('--pipeline-id')+1]),['ocid1.devopsdeploypipeline.a','ocid1.devopsdeploypipeline.b']);
 const aDone=r.calls.findIndex(c=>c.args.includes('get')&&c.args.includes('ocid1.devopsdeployment.a'));
 const bStart=r.calls.findIndex(c=>c.args.includes('create-pipeline-deployment')&&c.args.includes('ocid1.devopsdeploypipeline.b'));
 assert.ok(aDone<bStart);
});
test('independent components need no artificial Prometheus install dependency',()=>{
 const r=runPlatform({config:{components:{a:platformComponent('a'),b:platformComponent('b')}}},'deploy');assert.equal(r.status,0,r.stderr);
 assert.equal(r.calls.filter(c=>c.args.includes('create-pipeline-deployment')).length,2);
});
test('failed child stops dependent deployment and records failure',()=>{
 const r=runPlatform({failedChild:'.a'},'deploy');assert.notEqual(r.status,0);
 assert.equal(r.calls.filter(c=>c.args.includes('create-pipeline-deployment')).length,1);
 assert.equal(r.uploads[0].body.status,'failed');
});
test('cyclic dependency graph fails without launching children',()=>{
 const r=runPlatform({config:{components:{a:platformComponent('a',['b']),b:platformComponent('b',['a'])}}},'deploy');assert.notEqual(r.status,0);
 assert.equal(r.calls.length,1);assert.equal(r.uploads[0].body.status,'failed');
});
test('failed actual rollout and failed evidence upload cannot report success',()=>{
 for(const changes of [{failRollout:true},{failUpload:true},{badRelease:true},{staleOwner:true},{drift:true},{chartDrift:true},{metadataChanged:true}]){
  const r=runPlatform(changes);assert.notEqual(r.status,0);
 }
});
test('fresh validation normalizes v-prefixed chart versions returned by Helm metadata',()=>{
 const r=runPlatform({prefixedVersion:true});assert.equal(r.status,0,r.stderr);assert.equal(r.uploads[0].body.components.a.chart_version,'v1.0.0');
});
test('Prometheus validation requires Bound data PVC and KEDA API aggregation',()=>{
 const prometheus=platformComponent('prometheus'),keda=platformComponent('keda');
 const r=runPlatform({config:{components:{prometheus,keda}}});assert.equal(r.status,0,r.stderr);
 assert.ok(r.calls.some(c=>c.args.includes('apiservice/v1beta1.external.metrics.k8s.io')));
 assert.notEqual(runPlatform({config:{components:{prometheus}},badPvc:true}).status,0);
});
test('platform identity overrides are rejected before cloud calls',()=>{
 const r=runPlatform({},'validate',{CLUSTER_ID:'another-cluster'});assert.notEqual(r.status,0);assert.deepEqual(r.calls,[]);
});
