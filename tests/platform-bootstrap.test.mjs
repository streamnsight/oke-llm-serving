// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..');
const modulePath=`${root}/terraform/modules/platform-bootstrap`;
const components=JSON.parse(readFileSync(`${modulePath}/data/components.json`));
const gpu={metadata:{name:'gpu',labels:{'node.kubernetes.io/instance-type':'BM.GPU.A10.4'}},spec:{},status:{conditions:[{type:'Ready',status:'True'}],allocatable:{'nvidia.com/gpu':'4'}}};
const cpu={metadata:{name:'existing-cpu',labels:{'node.kubernetes.io/instance-type':'VM.Standard.E4.Flex'}},spec:{},status:{conditions:[{type:'Ready',status:'True'}],allocatable:{cpu:'8',memory:'22Gi'}}};
const config={platform_name:'fixture',region:'us-ashburn-1',cluster_id:'cluster',node_count:1,gpu_count_per_host:4,gpu_shapes:['BM.GPU.A10.4'],requires_rdma:false,enable_lws:true,target:{kubernetes_version:'v1.34.1'},generation:'a'.repeat(64),artifact_bucket:'private-platform',storage_namespace:'fixture',evidence_prefix:'fixture/generation',components};
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

// External commands are simulated; the real Bash runner, jq evaluation, binary
// checksums, archive extraction and evidence handling run together locally.
const mock=String.raw`
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const dir=process.env.MOCK_DIR, tool=path.basename(process.argv[1]), args=process.argv.slice(2);
const state=JSON.parse(fs.readFileSync(dir+'/state.json'));
state.calls.push({tool,args});
const save=()=>fs.writeFileSync(dir+'/state.json',JSON.stringify(state));
const out=value=>process.stdout.write(typeof value==='string'?value:JSON.stringify(value));
const arg=name=>args[args.indexOf(name)+1];
if(tool==='curl') {
 const url=args.find(x=>x.startsWith('https://')); let content;
 if(url.endsWith('/kubectl')) content=fs.readFileSync(dir+'/bin/kubectl');
 else if(url.endsWith('/kubectl.sha256')) content=crypto.createHash('sha256').update(fs.readFileSync(dir+'/bin/kubectl')).digest('hex');
 else if(url.endsWith('.sha256sum')) content=crypto.createHash('sha256').update(fs.readFileSync(dir+'/helm.tgz')).digest('hex');
 else content=fs.readFileSync(dir+'/helm.tgz');
 fs.writeFileSync(arg('-o'),content);
} else if(tool==='oci') {
 if(args[0]==='ce') fs.writeFileSync(arg('--file'),'mock kubeconfig');
 else if(args.slice(0,3).join(' ')==='os object put') state.uploads.push({name:arg('--name'),body:fs.readFileSync(arg('--file'),'utf8')});
 else throw Error('unexpected OCI mutation');
} else if(tool==='helm') {
 if(args[0]==='list') out(state.releases);
 else if(args[0]==='upgrade') {state.installed=true;}
 else throw Error('unexpected Helm action');
} else if(tool==='kubectl') {
 if(args[0]==='get'&&args[1]==='nodes') out({items:args.includes('-l')?[state.gpu]:[state.gpu,state.cpu]});
 else if(args[0]==='get'&&args[1]==='crd') {if(state.crd) out(state.crd);}
 else if(args[0]==='get'&&args[1]==='deployments') out({items:[{metadata:{name:'lws-controller-manager'}}]});
 else if(args[0]==='wait') {}
 else if(args[0]==='rollout') {if(state.failRollout){save();process.stderr.write('controller rollout failed');process.exit(1);}}
 else if(args[0]==='apply'&&args.includes('--dry-run=server')) out({kind:'LeaderWorkerSet'});
 else throw Error('unexpected Kubernetes mutation');
} else if(tool==='sleep') {} else throw Error('unexpected tool');
save();
`;
function runBootstrap(initial={}) {
  const dir=mkdtempSync(`${tmpdir()}/oke-platform-run-`);
  try {
    mkdirSync(`${dir}/bin`); mkdirSync(`${dir}/linux-amd64`);
    for(const tool of ['kubectl','helm','curl','oci','sleep']) writeFileSync(`${dir}/bin/${tool}`,`#!${process.execPath}\n${mock}`,{mode:0o755});
    writeFileSync(`${dir}/linux-amd64/helm`,readFileSync(`${dir}/bin/helm`),{mode:0o755});
    execFileSync('tar',['-czf',`${dir}/helm.tgz`,'-C',dir,'linux-amd64']);
    writeFileSync(`${dir}/state.json`,JSON.stringify({calls:[],uploads:[],releases:[],crd:null,gpu,cpu,...initial}));
    const result=spawnSync('bash',[`${modulePath}/scripts/bootstrap.sh`],{env:{...process.env,PATH:`${dir}/bin:${process.env.PATH}`,MOCK_DIR:dir,OCI_DEPLOYMENT_ID:'mock-run',CONFIG_B64:Buffer.from(JSON.stringify(config)).toString('base64'),READINESS_B64:readFileSync(`${modulePath}/scripts/readiness.jq`).toString('base64')},encoding:'utf8',timeout:20000});
    const state=JSON.parse(readFileSync(`${dir}/state.json`));
    return {...result,state,marker:JSON.parse(state.uploads.filter(x=>x.name.endsWith('/readiness.json')).at(-1).body)};
  } finally {rmSync(dir,{recursive:true,force:true});}
}
test('bootstrap installs only a shared controller and writes generation readiness',()=>{
  const result=runBootstrap(); assert.equal(result.status,0,result.stderr);
  assert.equal(result.marker.status,'ready'); assert.equal(result.marker.generation,config.generation);
  assert.equal(result.marker.controllers.lws.action,'installed');
  const install=result.state.calls.find(x=>x.tool==='helm'&&x.args[0]==='upgrade');
  const affinity=JSON.parse(install.args[install.args.indexOf('--set-json')+1].slice('affinity='.length));
  assert.ok(affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions.some(e=>e.operator==='NotIn'&&e.values.includes('BM.GPU.A10.4')));
  assert.ok(result.state.calls.some(x=>x.tool==='kubectl'&&x.args.includes('--dry-run=server')));
  assert.equal(result.state.calls.filter(x=>x.tool==='oci'&&x.args[0]==='ce').length,1,'only kubeconfig creation may use OCI CE');
  assert.equal(result.marker.model_runtime_validation,'not_run');
});
test('ordinary Helm crds without ownership annotations reuse a unique existing release',()=>{
  const result=runBootstrap({crd:{metadata:{annotations:{}}},releases:[{name:'existing-lws',namespace:'existing-system',chart:'lws-1.0.0',status:'deployed'}]});
  assert.equal(result.status,0,result.stderr); assert.equal(result.marker.controllers.lws.action,'reused');
  assert.equal(result.state.calls.filter(x=>x.tool==='helm'&&x.args[0]==='upgrade').length,0);
});
test('unknown controller ownership fails without adoption or a success marker',()=>{
  const result=runBootstrap({crd:{metadata:{annotations:{}}}});
  assert.notEqual(result.status,0); assert.equal(result.marker.status,'failed');
  assert.match(result.stderr,/review ownership/);
  assert.equal(result.state.calls.filter(x=>x.tool==='helm'&&x.args[0]==='upgrade').length,0);
});
test('a different chart version is reported rather than automatically upgraded',()=>{
  const result=runBootstrap({crd:{metadata:{annotations:{}}},releases:[{name:'existing-lws',namespace:'existing-system',chart:'lws-0.9.0',status:'deployed'}]});
  assert.notEqual(result.status,0); assert.match(result.stderr,/no adoption or upgrade/);
  assert.equal(result.marker.status,'failed');
  assert.equal(result.state.calls.filter(x=>x.tool==='helm'&&x.args[0]==='upgrade').length,0);
});
test('rollout failure replaces in-progress evidence with failed readiness',()=>{
  const result=runBootstrap({failRollout:true}); assert.notEqual(result.status,0);
  assert.equal(result.marker.status,'failed'); assert.match(result.stderr,/rollout failed/);
});
