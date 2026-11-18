// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,existsSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve,dirname} from 'node:path';
const launcher=resolve(import.meta.dirname,'../modules/llm-deployment/model-delivery/chart/files/lmcache-launch.sh');
const check=readFileSync(launcher,'utf8').match(/python3 - "\$LMCACHE_ADAPTER" <<'PY'\n([\s\S]*?)\nPY/)[1];
function fixture({mode='inprocess',hybrid=true,supported=false,api=true}={}){
 const dir=mkdtempSync(`${tmpdir()}/lmcache-capability-`);
 const files={
  'lmcache/integration/vllm/vllm_v1_adapter.py':'',
  'lmcache/integration/vllm/lmcache_mp_connector.py':'',
  'vllm/config.py':'class KVTransferConfig:\n def __init__(self,**kwargs): self.__dict__.update(kwargs)\n',
  'vllm/distributed/kv_transfer/kv_connector/factory.py':`import json,os\nclass KVConnectorFactory:\n @classmethod\n def supports_hma_config(cls,config):\n  open(os.environ['CAPTURE']+'/factory.json','w').write(json.dumps(config.__dict__))\n  return ${supported?'True':'False'}\n${api?'':"del KVConnectorFactory.supports_hma_config\n"}`,
  'bin/vllm':'#!/bin/sh\ntouch "$CAPTURE/model-started"\nexit 7\n',
  'bin/lmcache':'#!/bin/sh\ntouch "$CAPTURE/cache-started"\nexit 7\n'
 };
 for(const [name,content] of Object.entries(files)){const path=`${dir}/${name}`;mkdirSync(dirname(path),{recursive:true});writeFileSync(path,content,{mode:name.startsWith('bin/')?0o755:0o644});}
 const env={...process.env,PYTHONPATH:dir,CAPTURE:dir,PATH:`${dir}/bin:${process.env.PATH}`,LMCACHE_ADAPTER:mode,LMCACHE_REQUIRES_HMA:String(hybrid),LMCACHE_CPU_MEMORY_GB:'8',LMCACHE_CHUNK_SIZE:'256'};
 return{dir,preflight(){return spawnSync('python3',['-c',check,mode],{env,encoding:'utf8',timeout:10000});},launch(){return spawnSync('bash',[launcher,'org/model'],{env,encoding:'utf8',timeout:10000});},close(){rmSync(dir,{recursive:true,force:true});}};
}
test('hybrid cache incompatibility fails before starting inference or a cache server',()=>{
 for(const mode of ['inprocess','mp']){const f=fixture({mode});try{const r=f.launch();assert.notEqual(r.status,0);assert.match(r.stderr,/does not support the hybrid memory allocator/);assert(!existsSync(`${f.dir}/model-started`));assert(!existsSync(`${f.dir}/cache-started`));}finally{f.close();}}
});
test('future HMA-capable connectors pass using the selected connector configuration',()=>{
 for(const mode of ['inprocess','mp']){const f=fixture({mode,supported:true});try{const r=f.preflight();assert.equal(r.status,0,r.stderr);const c=JSON.parse(readFileSync(`${f.dir}/factory.json`));assert.equal(c.kv_connector,mode==='mp'?'LMCacheMPConnector':'LMCacheConnectorV1');assert.equal(c.kv_connector_module_path,mode==='mp'?'lmcache.integration.vllm.lmcache_mp_connector':null);}finally{f.close();}}
});
test('ordinary attention models do not require the hybrid-only factory API',()=>{
 const f=fixture({hybrid:false,api:false});try{const r=f.launch();assert.equal(r.status,7,r.stderr);assert(existsSync(`${f.dir}/model-started`));assert(!existsSync(`${f.dir}/factory.json`));}finally{f.close();}
});
test('unverifiable hybrid support fails with an actionable compatibility error',()=>{
 const f=fixture({api:false});try{const r=f.preflight();assert.notEqual(r.status,0);assert.match(r.stderr,/Cannot verify hybrid-cache support/);}finally{f.close();}
});
