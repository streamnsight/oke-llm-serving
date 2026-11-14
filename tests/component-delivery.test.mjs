// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync,copyFileSync,existsSync,readdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';

const modulePath=resolve(import.meta.dirname,'../modules/component-delivery');
const spec={component:'lws',platform:'fixture',cluster_id:'cluster',region:'eu-frankfurt-1',mode:'managed',namespace:'lws-system',release_name:'lws',ownership_token:'stable-platform-owner',chart:{repository:'oci://registry.k8s.io/lws/charts',name:'lws',version:'1.0.0'},mirror_url:'oci://eu-frankfurt-1.ocir.io/fixture/lws',lock_name:'fixture-lock',lock_duration_seconds:3600,timeout_seconds:600,parameters:{REPLICAS:'2'},values_yaml:'{"replicas":"${REPLICAS}"}',dependencies:[],crd_names:['leaderworkersets.example.org'],deployment_names:['controller'],blocker_kinds:['leaderworkersets.example.org']};
// Only external services/tool installation are simulated. The production Bash,
// ownership/retention guards, CAS lease logic and evidence construction run.
const mock=String.raw`
const fs=require('node:fs'),path=require('node:path');
const file=process.env.MOCK_STATE, state=JSON.parse(fs.readFileSync(file)), tool=path.basename(process.argv[1]), a=process.argv.slice(2);
const arg=n=>a[a.indexOf(n)+1],out=v=>process.stdout.write(typeof v==='string'?v:JSON.stringify(v));
let input;const body=()=>input??=(arg('-f')==='-'?fs.readFileSync(0,'utf8'):fs.readFileSync(arg('-f'),'utf8'));
const fail=message=>{save();process.stderr.write(message);process.exit(1);};
const save=()=>fs.writeFileSync(file,JSON.stringify(state));
const registryAuth=()=>{
 const config=arg('--registry-config');if(!config||config!==process.env.HELM_REGISTRY_CONFIG)fail('Explicit Helm registry config required');
 const mode=fs.statSync(config).mode&0o777,entry=JSON.parse(fs.readFileSync(config)).auths[process.env.DELIVERY_REGISTRY_HOST];
 if(mode!==0o600||entry.registrytoken!=='fixture.token.signature'||Object.keys(entry).join(',')!=='registrytoken')fail('Expected private direct-access-token configuration');
 (state.authChecks??=[]).push({path:config,mode,keys:Object.keys(entry)});
};
state.calls.push({tool,args:a});
if(tool==='kubectl') {
 const verb=a.find(x=>['get','create','replace','apply','wait','rollout','api-resources'].includes(x)),i=a.indexOf(verb),kind=a[i+1];
 if(verb==='get'&&kind==='lease') {if(state.lease)out(state.lease);else if(!a.includes('--ignore-not-found'))fail('NotFound');}
 else if(verb==='get'&&kind==='configmap') {if(state.owner)out(state.owner);else if(!a.includes('--ignore-not-found'))fail('NotFound');}
 else if(verb==='get'&&kind==='crd') {const crd=(state.crds||{})[a[i+2]];if(crd)out(crd);else if(!a.includes('--ignore-not-found'))fail('NotFound');}
 else if(verb==='api-resources'){if(state.discoveryFailure)fail('Forbidden');out((state.servedKinds||['leaderworkersets.example.org']).join('\n')+'\n');}
 else if(verb==='get') out({items:state.blockers||[]});
 else if(verb==='create'&&kind==='namespace')out({apiVersion:'v1',kind:'Namespace',metadata:{name:a[i+2]}});
 else if(verb==='create') {const next=JSON.parse(body());if(next.kind==='CustomResourceDefinition'){state.crds??={};if(state.crds[next.metadata.name])fail('AlreadyExists');state.crds[next.metadata.name]=next;}else{if(state.lease)fail('AlreadyExists');state.lease=next;state.lease.metadata.resourceVersion='1';}}
 else if(verb==='replace') {const next=JSON.parse(body());if(state.conflict||next.metadata.resourceVersion!==state.lease.metadata.resourceVersion)fail('Conflict');next.metadata.resourceVersion=String(Number(next.metadata.resourceVersion)+1);state.lease=next;}
 else if(verb==='apply') {const next=JSON.parse(body());if(next.kind==='ConfigMap')state.owner=next;else if(next.kind==='CustomResourceDefinition'){if(state.crdConflict)fail('field conflict');state.crds[next.metadata.name]=next;}}
 else if(verb==='wait'||verb==='rollout') {if(state.notReady)fail('NotReady');}
 else fail('unexpected Kubernetes command');
} else if(tool==='helm') {
 if(a[0]==='list')out(state.releases||[]);
 else if(a[0]==='status') {if(state.notReady)fail('NotReady');out({version:state.installedRevision??3,info:{status:'deployed'},chart:{metadata:{name:'lws',version:state.installedVersion||'1.0.0'}}});}
 else if(a[0]==='pull') {if(arg('--destination')==='mirrored'){registryAuth();if(state.mirrorForbidden)fail('403 Anonymous users are only allowed read access on public repos');if(!state.mirrored)fail('manifest not found: 404');}fs.mkdirSync(arg('--destination'),{recursive:true});fs.writeFileSync(path.join(arg('--destination'),'lws-1.0.0.tgz'),'chart');}
 else if(a[0]==='show'){if(a[1]==='crds')out(state.crdBundle||[]);else out({name:'lws'});}
 else if(a[0]==='get'&&a[1]==='values')out(state.installedValues||{replicas:process.env.REPLICAS});
 else if(a[0]==='template'||a[0]==='get')out(state.manifest||{apiVersion:'apps/v1',kind:'Deployment',metadata:{name:'controller'}});
 else if(a[0]==='push'){registryAuth();state.mirrored=true;}
 else if(a[0]==='uninstall'){state.uninstalled=true;state.releases=[];}
 else fail('Unexpected Helm command, including Basic registry login or Shell install/upgrade');
} else if(tool==='oci') {
 if(a[0]==='raw-request'){
   if(a.includes('--query')||a.includes('--raw-output'))fail('raw-request wrapper must be parsed locally');
   let data=Object.hasOwn(state,'tokenData')?state.tokenData:{token:state.emptyToken?'':'fixture.token.signature'};
   if(state.tokenDataString)data=JSON.stringify(data);
   out({status:state.tokenStatus??'200 OK',headers:{'content-type':'application/json'},data});
 }
 else if(a[0]==='devops')out(state.previousState||'FAILED');
 else if(a.slice(0,4).join(' ')==='artifacts generic artifact upload-by-path'){if(!a.includes('--content-body'))fail('Missing OCI --content-body');if(state.failUpload)fail('Upload failed');state.results.push(JSON.parse(fs.readFileSync(arg('--content-body'),'utf8')));}
 else fail('unexpected OCI command');
} else if(tool==='yq') {
 if(a.includes('.name'))out(JSON.parse(fs.readFileSync(0,'utf8')).name);
 else if(a[0]==='-o=json')out(JSON.parse(fs.readFileSync(a.at(-1),'utf8')));
 else if(a[0]==='-e'){const data=JSON.parse(fs.readFileSync(a.at(-1),'utf8'));if(!data||Array.isArray(data)||typeof data!=='object')fail('not map');}
 else {const data=JSON.parse(fs.readFileSync(a.at(-1),'utf8'));for(const d of(Array.isArray(data)?data:[data]))if(a.includes('.')||(a.some(x=>x.includes('PersistentVolumeClaim'))?['CustomResourceDefinition','PersistentVolumeClaim']:['CustomResourceDefinition']).includes(d.kind))out(JSON.stringify(d)+'\n');}
} else fail('unexpected tool');
save();
`;
function fixture(initial={}) {
  const dir=mkdtempSync(`${tmpdir()}/component-delivery-`);
  mkdirSync(`${dir}/bin`);
  for(const tool of ['kubectl','helm','oci','yq'])writeFileSync(`${dir}/bin/${tool}`,`#!${process.execPath}\n${mock}`,{mode:0o755});
  for(const script of ['component.sh','lock.sh'])copyFileSync(`${modulePath}/scripts/${script}`,`${dir}/${script}`);
  writeFileSync(`${dir}/tools.sh`,'delivery_tools() { :; }\n');
  writeFileSync(`${dir}/specification.json`,JSON.stringify(spec));
  writeFileSync(`${dir}/state.json`,JSON.stringify({calls:[],results:[],...initial}));
  const env={...process.env,PATH:`${dir}/bin:${process.env.PATH}`,MOCK_STATE:`${dir}/state.json`,OCI_DEPLOYMENT_ID:'deployment-current',OCI_PIPELINE_ID:'pipeline-current',DELIVERY_GENERATION:'generation',DELIVERY_RESULT_REPOSITORY:'results',DELIVERY_REGION:spec.region,DELIVERY_REGISTRY_HOST:'eu-frankfurt-1.ocir.io',CHART_VERSION:'1.0.0',REPLICAS:'2',CONFIRM_UNINSTALL:'false'};
  return {dir,env,run(operation,overrides={}){const result=spawnSync('bash',['./component.sh'],{cwd:dir,env:{...env,DELIVERY_OPERATION:operation,...overrides},encoding:'utf8',timeout:20000});return {...result,state:JSON.parse(readFileSync(`${dir}/state.json`))};},read(){return JSON.parse(readFileSync(`${dir}/state.json`));},set(next){writeFileSync(`${dir}/state.json`,JSON.stringify(next));},close(){rmSync(dir,{recursive:true,force:true});}};
}
const lease=(holder='deployment-old',owner=spec.ownership_token,age=7200)=>({apiVersion:'coordination.k8s.io/v1',kind:'Lease',metadata:{name:spec.lock_name,resourceVersion:'1',annotations:{'oke-llm/owner-token':owner,'oke-llm/acquired-epoch':String(Math.floor(Date.now()/1000)-age)}},spec:{holderIdentity:holder,leaseDurationSeconds:3600}});
const owned={metadata:{name:'owner'},data:{ownership_token:spec.ownership_token}};

test('managed prepare mirrors chart, locks across native stage, validates and releases after finish',()=>{
  const f=fixture();try{
    let r=f.run('prepare');assert.equal(r.status,0,r.stderr);assert.equal(r.state.lease.spec.holderIdentity,'deployment-current');assert.equal(r.state.owner.data.status,'applying');assert.equal(r.state.owner.data.helm_revision,'');assert.equal(r.state.results.at(-1).status,'prepared');assert.equal(r.state.results.at(-1).helm_revision,null);
    assert.equal(existsSync(`${f.dir}/helm-status.json`),false);
    f.set({...f.read(),releases:[{name:'lws'}],installedVersion:'v1.0.0'});
    r=f.run('finish');assert.equal(r.status,0,r.stderr);assert.equal(r.state.lease.spec.holderIdentity,'');assert.equal(r.state.owner.data.status,'ready');assert.equal(r.state.results.at(-1).effective_parameters.REPLICAS,'2');
    assert.equal(r.state.owner.data.helm_revision,'3');assert.equal(r.state.results.at(-1).helm_revision,3);
    assert.equal(JSON.parse(readFileSync(`${f.dir}/helm-status.json`)).chart.metadata.version,'v1.0.0');
    assert(!r.state.calls.some(x=>x.tool==='helm'&&['upgrade','install'].includes(x.args[0])));
  }finally{f.close();}
});
test('explicit predefined-variable binding correlates prepare and finish; missing identity fails before mutation',()=>{
  const f=fixture();try{
    const bound={OCI_DEPLOYMENT_ID:'',OCI_PIPELINE_ID:'',DELIVERY_DEPLOYMENT_ID:'deployment-current',DELIVERY_PIPELINE_ID:'pipeline-current'};
    let r=f.run('prepare',bound);assert.equal(r.status,0,r.stderr);assert.equal(r.state.lease.spec.holderIdentity,'deployment-current');
    f.set({...f.read(),releases:[{name:'lws'}]});r=f.run('finish',bound);assert.equal(r.status,0,r.stderr);assert.equal(r.state.results.at(-1).deployment_id,'deployment-current');assert.equal(r.state.results.at(-1).pipeline_id,'pipeline-current');
  }finally{f.close();}
  for(const binding of ['', '${OCI_DEPLOYMENT_ID}']){
    const missing=fixture();try{const r=missing.run('prepare',{OCI_DEPLOYMENT_ID:'',DELIVERY_DEPLOYMENT_ID:binding});assert.notEqual(r.status,0);assert.equal(r.state.calls.length,0);assert.match(r.stderr,/predefined OCI_DEPLOYMENT_ID/);}finally{missing.close();}
  }
});
test('registry direct access token uses private config, never leaks, and is removed after success or failure',()=>{
  for(const [extra,ok] of [[{},true],[{tokenDataString:true},true],[{tokenStatus:200},true],[{mirrorForbidden:true},false],[{emptyToken:true},false],[{tokenStatus:'401 Unauthorized'},false],[{tokenData:null},false],[{tokenData:'malformed fixture.token.signature'},false],[{tokenData:{}},false],[{tokenData:{token:null}},false],[{tokenData:{token:'null'}},false],[{tokenData:{token:123}},false]]){
    const f=fixture(extra);try{
      const r=f.run('prepare');assert.equal(r.status===0,ok,r.stderr);
      if(ok||extra.mirrorForbidden){assert(r.state.authChecks.length>0);assert(r.state.authChecks.every(x=>x.mode===0o600&&x.keys.join(',')==='registrytoken'&&!existsSync(x.path)));}else{assert(!r.state.authChecks?.length);}
      assert(!readdirSync(f.dir).some(name=>name.startsWith('.delivery-registry')));
      assert(!JSON.stringify({stdout:r.stdout,stderr:r.stderr,calls:r.state.calls,results:r.state.results}).includes('fixture.token.signature'));
      assert(!r.state.calls.some(x=>x.tool==='helm'&&x.args[0]==='registry'));
      if(r.status!==0)assert.equal(r.state.lease.spec.holderIdentity,'');
    }finally{f.close();}
  }
});
test('foreign release is not adopted and reuse validates without lock or install',()=>{
  const f=fixture({releases:[{name:'lws'}]});try{
    let r=f.run('prepare');assert.notEqual(r.status,0);assert.equal(r.state.lease.spec.holderIdentity,'');assert(!r.state.mirrored);
    f.set({calls:[],results:[],releases:[{name:'lws'}]});r=f.run('reuse');assert.equal(r.status,0,r.stderr);assert.equal(r.state.lease,undefined);assert.equal(r.state.owner,undefined);assert.equal(r.state.results.at(-1).status,'ready');
  }finally{f.close();}
});
test('reuse fails when evidence upload fails inside the EXIT trap',()=>{
  const f=fixture({failUpload:true,releases:[{name:'lws'}]});try{
    const r=f.run('reuse');assert.notEqual(r.status,0);assert.equal(r.state.results.length,0);assert.equal(r.state.owner,undefined);assert.equal(r.state.lease,undefined);assert(r.state.calls.some(x=>x.tool==='oci'&&x.args.slice(0,4).join(' ')==='artifacts generic artifact upload-by-path'));
  }finally{f.close();}
});
test('finish rejects changed arguments, wrong installed versions and mismatched native Helm values',()=>{
  for(const change of [{overrides:{REPLICAS:'3'}},{installedVersion:'2.0.0'},{installedValues:{replicas:'99'}},{installedRevision:0}]){
    const f=fixture();try{const prepared=f.run('prepare');assert.equal(prepared.status,0,prepared.stderr);f.set({...f.read(),releases:[{name:'lws'}],...change});const r=f.run('finish',change.overrides);assert.notEqual(r.status,0);assert.equal(r.state.owner.data.status,'applying');assert.equal(r.state.results.at(-1).status,'failed');assert.equal(r.state.lease.spec.holderIdentity,'');}finally{f.close();}
  }
});
test('expired lock requires exact holder and terminal OCI deployment; active deployment fails closed',()=>{
  for(const [overrides,previousState,ok] of [[{},'FAILED',false],[{RECOVER_LOCK_HOLDER:'wrong'},'FAILED',false],[{RECOVER_LOCK_HOLDER:'deployment-old'},'IN_PROGRESS',false],[{RECOVER_LOCK_HOLDER:'deployment-old'},'FAILED',true]]){
    const f=fixture({lease:lease(),previousState});try{const r=f.run('prepare',overrides);assert.equal(r.status===0,ok,r.stderr);if(!ok)assert.equal(r.state.lease.spec.holderIdentity,'deployment-old');}finally{f.close();}
  }
});
test('unexpired lock and compare-and-swap conflict prevent takeover',()=>{
  for(const state of [{lease:lease('deployment-old',spec.ownership_token,0)},{lease:lease(''),conflict:true}]){
    const f=fixture(state);try{const r=f.run('prepare',{RECOVER_LOCK_HOLDER:'deployment-old'});assert.notEqual(r.status,0);assert(!r.state.mirrored);}finally{f.close();}
  }
});
test('uninstall needs confirmation, owned release, no consumers and retained CRDs/PVCs',()=>{
  const cases=[{overrides:{},ok:false},{overrides:{CONFIRM_UNINSTALL:'true'},owner:undefined,ok:false},{overrides:{CONFIRM_UNINSTALL:'true'},blockers:[{}],ok:false},{overrides:{CONFIRM_UNINSTALL:'true'},manifest:{kind:'CustomResourceDefinition',metadata:{name:'unsafe'}},ok:false},{overrides:{CONFIRM_UNINSTALL:'true'},manifest:{kind:'PersistentVolumeClaim',metadata:{name:'data'}},ok:false},{overrides:{CONFIRM_UNINSTALL:'true'},manifest:{kind:'CustomResourceDefinition',metadata:{annotations:{'helm.sh/resource-policy':'keep'}}},ok:true}];
  for(const c of cases){const f=fixture({releases:[{name:'lws'}],owner:owned,...c});try{const r=f.run('undeploy',c.overrides);assert.equal(r.status===0,c.ok,r.stderr);assert.equal(!!r.state.uninstalled,c.ok);if(r.state.lease)assert.equal(r.state.lease.spec.holderIdentity,'');}finally{f.close();}}
});
test('unsafe templated CRD and evidence upload failures stop native deployment before prepare succeeds',()=>{
  for(const extra of [{manifest:{kind:'CustomResourceDefinition',metadata:{name:'unsafe'}}},{manifest:{kind:'List',items:[{kind:'CustomResourceDefinition',metadata:{name:'unsafe'}}]}},{failUpload:true}]){
    const f=fixture(extra);try{const r=f.run('prepare');assert.notEqual(r.status,0);assert.equal(r.state.lease.spec.holderIdentity,'');}finally{f.close();}
  }
});
test('raw CRDs are created with ownership and retained; only owned CRDs receive non-forcing server-side updates',()=>{
  const crd={apiVersion:'apiextensions.k8s.io/v1',kind:'CustomResourceDefinition',metadata:{name:'leaderworkersets.example.org'},spec:{group:'example.org'}};
  for(const [existing,conflict,ok] of [[undefined,false,true],[crd,false,false],[{...crd,metadata:{...crd.metadata,annotations:{'oke-llm/owner-token':spec.ownership_token}}},false,true],[{...crd,metadata:{...crd.metadata,annotations:{'oke-llm/owner-token':spec.ownership_token}}},true,false]]){
    const f=fixture({crdBundle:[crd],crds:existing?{[crd.metadata.name]:existing}:{},crdConflict:conflict});try{
      const r=f.run('prepare');assert.equal(r.status===0,ok,r.stderr);
      if(ok){assert.equal(r.state.crds[crd.metadata.name].metadata.annotations['helm.sh/resource-policy'],'keep');assert.equal(r.state.crds[crd.metadata.name].metadata.annotations['oke-llm/owner-token'],spec.ownership_token);}
      assert(!r.state.calls.some(x=>x.args.includes('--force-conflicts')));
    }finally{f.close();}
  }
});
test('uninstall excludes exact owned manifest consumers, tolerates absent APIs and rejects discovery errors',()=>{
  const own={apiVersion:'example.org/v1',kind:'LeaderWorkerSet',metadata:{name:'own',namespace:spec.namespace}};
  const cases=[{manifest:own,blockers:[own],ok:true},{manifest:own,blockers:[{...own,metadata:{...own.metadata,name:'external'}}],ok:false},{servedKinds:[],blockers:[{}],ok:true},{discoveryFailure:true,ok:false}];
  for(const c of cases){const f=fixture({releases:[{name:'lws'}],owner:owned,...c});try{const r=f.run('undeploy',{CONFIRM_UNINSTALL:'true'});assert.equal(r.status===0,c.ok,r.stderr);assert.equal(!!r.state.uninstalled,c.ok);}finally{f.close();}}
});
test('Shell sources parse with Bash',()=>{
  for(const file of ['component.sh','lock.sh','tools.sh'])execFileSync('bash',['-n',`${modulePath}/scripts/${file}`]);
});
