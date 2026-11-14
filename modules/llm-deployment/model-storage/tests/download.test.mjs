// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const moduleDir = resolve(fileURLToPath(new URL('..', import.meta.url)));
const hash = value => createHash('sha256').update(value).digest('hex');
const content = 'bounded snapshot payload\n';
const fakeToken = 'hf_TestFixtureNotACredential';

const ociMock = String.raw`#!/usr/bin/env node
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const args = process.argv.slice(2), option = name => args[args.indexOf(name)+1];
const root = process.env.MOCK_OS_DIR;
fs.appendFileSync(path.join(root,'calls'), JSON.stringify({args,auth:process.env.OCI_CLI_AUTH})+'\n');
if(process.env.OCI_CLI_AUTH!=='oke_workload_identity') process.exit(91);
if(args.slice(0,3).join(' ')==='os bucket get') {
  if(process.env.MOCK_AUTH_FAILURE) process.exit(93);
  console.log('{}'); process.exit(0);
}
if(args.slice(0,3).join(' ')==='secrets secret-bundle get') {
  console.log(Buffer.from(process.env.MOCK_HF_TOKEN).toString('base64')); process.exit(0);
}
const name=option('--name'), prefix=option('--prefix');
const objectFile = key => path.join(root,crypto.createHash('sha256').update(key).digest('hex'));
if(args.slice(0,3).join(' ')==='os object list') {
  if(process.env.MOCK_LIST_FAILURE) process.exit(94);
  const objects = JSON.parse(fs.readFileSync(path.join(root,'objects'),'utf8'));
  console.log(JSON.stringify({data:objects.filter(x=>x.startsWith(prefix)).map(name=>({name}))})); process.exit(0);
}
if(args.slice(0,3).join(' ')==='os object head') {
  console.log(fs.readFileSync(objectFile(name)+'.json','utf8')); process.exit(0);
}
if(args.slice(0,3).join(' ')==='os object put') {
  if(process.env.MOCK_FAIL_FIRST_UPLOAD && !name.endsWith('/manifest.json') && !fs.existsSync(path.join(root,'upload-failed'))) {
    fs.writeFileSync(path.join(root,'upload-failed'),'yes'); process.exit(95);
  }
  if(fs.existsSync(objectFile(name))) process.exit(0);
  const body=fs.readFileSync(option('--file')), metadata=args.includes('--metadata')?JSON.parse(option('--metadata')):{};
  fs.writeFileSync(objectFile(name),body);
  fs.writeFileSync(objectFile(name)+'.json',JSON.stringify({'content-length':body.length,...Object.fromEntries(Object.entries(metadata).map(([k,v])=>['opc-meta-'+k,v]))}));
  const objects = JSON.parse(fs.readFileSync(path.join(root,'objects'),'utf8'));
  objects.push(name); fs.writeFileSync(path.join(root,'objects'),JSON.stringify(objects)); process.exit(0);
}
if(args.slice(0,3).join(' ')==='os object get') {
  fs.copyFileSync(objectFile(name),option('--file')); process.exit(0);
}
process.exit(99);
`;
const curlMock = String.raw`#!/usr/bin/env node
const fs=require('node:fs'),path=require('node:path');
const args=process.argv.slice(2),root=process.env.MOCK_OS_DIR;
fs.appendFileSync(path.join(root,'curl-calls'),JSON.stringify(args)+'\n');
if(args.some(x=>x.includes(process.env.MOCK_HF_TOKEN))) process.exit(97);
if(process.env.MOCK_REQUIRE_TOKEN) {
  const header=args.find(x=>x.startsWith('@'));
  if(!header || fs.readFileSync(header.slice(1),'utf8')!=='Authorization: Bearer '+process.env.MOCK_HF_TOKEN+'\n') process.exit(98);
}
const output=args[args.indexOf('--output')+1], body=Buffer.from(process.env.MOCK_CONTENT);
if(process.env.MOCK_PARTIAL_ONCE && !fs.existsSync(path.join(root,'partial'))) {
  fs.writeFileSync(output,body.subarray(0,8)); fs.writeFileSync(path.join(root,'partial'),'yes'); process.exit(18);
}
const offset=fs.existsSync(output)?fs.statSync(output).size:0;
fs.appendFileSync(output,body.subarray(offset));
`;

function fixture(t, extraEnv = {}) {
  const root = mkdtempSync(join(tmpdir(), 'model-storage-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  for (const dir of ['input', 'work', 'bin', 'objects']) mkdirSync(join(root, dir));
  copyFileSync(join(moduleDir, 'scripts', 'validate.jq'), join(root, 'input', 'validate.jq'));
  for (const [name, source] of [['oci', ociMock], ['curl', curlMock], ['sleep', '#!/bin/sh\nexit 0\n']]) {
    writeFileSync(join(root, 'bin', name), source, { mode: 0o755 });
  }
  writeFileSync(join(root, 'objects', 'objects'), '[]');
  const config = {
    schema_version: '1.0', model: { id: 'owner/model', revision: 'a'.repeat(40), variant: 'bf16', files: [{ path: 'model.safetensors', size_bytes: Buffer.byteLength(content), sha256: hash(content) }] },
    snapshot_sha256: 'b'.repeat(64), region: 'eu-frankfurt-1', storage_namespace: 'fixture', bucket: 'private-weights', prefix: 'models/owner--model/snapshot',
    owner: 'c'.repeat(24), namespace: 'fixture-staging', service_account: 'model-stager', pvc_name: 'fixture-download', scratch_gib: 64, storage_class: 'oci-bv',
    cpu_node_selector: { 'node-pool': 'cpu' }, hf_token_secret_id: null
  };
  function run() {
    writeFileSync(join(root, 'input', 'model.json'), JSON.stringify(config));
    return spawnSync('bash', [join(moduleDir, 'scripts', 'download.sh')], { encoding: 'utf8', env: {
      ...process.env, PATH: `${join(root, 'bin')}:${process.env.PATH}`, MODEL_INPUT_DIR: join(root, 'input'), MODEL_WORK_DIR: join(root, 'work'),
      MOCK_OS_DIR: join(root, 'objects'), MOCK_CONTENT: content, MOCK_HF_TOKEN: fakeToken, STAGING_IMAGE: `image@sha256:${'d'.repeat(64)}`,
      ...extraEnv
    }});
  }
  const objects = () => JSON.parse(readFileSync(join(root, 'objects', 'objects'), 'utf8'));
  const curls = () => existsSync(join(root, 'objects', 'curl-calls')) ? readFileSync(join(root, 'objects', 'curl-calls'), 'utf8').trim().split('\n').map(JSON.parse) : [];
  const stored = key => readFileSync(join(root, 'objects', hash(key)), 'utf8');
  return { root, config, run, objects, curls, stored };
}

test('stages only the selected file and publishes completion last; rerun reuses verified remote objects', t => {
  const f = fixture(t);
  let result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(f.objects(), [`${f.config.prefix}/files/model.safetensors`, `${f.config.prefix}/manifest.json`]);
  const manifest = JSON.parse(f.stored(`${f.config.prefix}/manifest.json`));
  assert.equal(manifest.files[0].sha256, hash(content));
  assert.equal(manifest.auth, 'oke_workload_identity');
  assert.equal(f.curls().length, 1);
  result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(f.curls().length, 1, 'existing verified object must avoid another Hub download');
});

test('failed upload preserves completed local shard and retry avoids downloading it again', t => {
  const f = fixture(t, { MOCK_FAIL_FIRST_UPLOAD: 'true' });
  assert.notEqual(f.run().status, 0);
  assert.deepEqual(f.objects(), [], 'failed transfer must not publish completion');
  assert.equal(existsSync(join(f.root, 'work', f.config.snapshot_sha256, `${hash('model.safetensors')}.part`)), true);
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(f.curls().length, 1);
});

test('interrupted HTTP transfer resumes from partial content with bounded retries', t => {
  const f = fixture(t, { MOCK_PARTIAL_ONCE: 'true' });
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(f.curls().length, 2);
  assert.equal(f.stored(`${f.config.prefix}/files/model.safetensors`), content);
});

test('source checksum mismatch refuses manifest publication and clears corrupt partial', t => {
  const f = fixture(t);
  f.config.model.files[0].sha256 = 'e'.repeat(64);
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /checksum mismatch/);
  assert.deepEqual(f.objects(), []);
  assert.equal(existsSync(join(f.root, 'work', f.config.snapshot_sha256, `${hash('model.safetensors')}.part`)), false);
});

test('traversal and missing permissions fail before downloading rather than claiming absence', t => {
  const bad = fixture(t);
  bad.config.model.files[0].path = '../unsafe';
  assert.notEqual(bad.run().status, 0);
  assert.equal(bad.curls().length, 0);
  const unauthorized = fixture(t, { MOCK_LIST_FAILURE: 'true' });
  assert.notEqual(unauthorized.run().status, 0);
  assert.equal(unauthorized.curls().length, 0);
  assert.deepEqual(unauthorized.objects(), []);
});

test('Vault token is consumed through a private header file without appearing in arguments or logs', t => {
  const f = fixture(t, { MOCK_REQUIRE_TOKEN: 'true' });
  f.config.hf_token_secret_id = 'ocid1.vaultsecret.oc1.fixture';
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal((result.stdout + result.stderr + JSON.stringify(f.curls())).includes(fakeToken), false);
});

test('Job renderer confines staging to an explicit CPU pool with workload identity and bounded storage', () => {
  const config = { namespace: 'fixture-staging', owner: 'c'.repeat(24), service_account: 'model-stager', region: 'eu-frankfurt-1', pvc_name: 'fixture-download', cpu_node_selector: { 'node-pool': 'cpu' } };
  const result = spawnSync('jq', ['--arg', 'name', 'fixture-download', '--arg', 'configmap', 'run-config', '--arg', 'image', `image@sha256:${'d'.repeat(64)}`, '--arg', 'deadline', '300', '--arg', 'run_id', 'unique-run', '-f', join(moduleDir, 'scripts', 'job.jq')], { input: JSON.stringify(config), encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const job = JSON.parse(result.stdout), pod = job.spec.template.spec;
  assert.equal(job.spec.activeDeadlineSeconds, 300);
  assert.equal(pod.nodeSelector['node-pool'], 'cpu');
  assert.equal(pod.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions.length, 3);
  assert.equal(pod.containers[0].env.find(v => v.name === 'OCI_CLI_AUTH').value, 'oke_workload_identity');
  assert.equal(pod.containers[0].resources.requests.cpu, '2');
  assert.equal(pod.containers[0].resources.requests['nvidia.com/gpu'], undefined);
  assert.equal(pod.volumes.find(v => v.name === 'scratch').persistentVolumeClaim.claimName, 'fixture-download');
});

const kubectlMock = String.raw`#!/usr/bin/env node
const fs=require('node:fs'),path=require('node:path');
const raw=process.argv.slice(2),args=[...raw],root=process.env.MOCK_OS_DIR;
fs.appendFileSync(path.join(root,'kubectl-calls'),JSON.stringify(raw)+'\n');
if(args[0]==='-n') args.splice(0,2);
const owner=process.env.MOCK_FOREIGN_PVC && args[1]?.startsWith('pvc/') ? 'foreign' : 'c'.repeat(24);
if(args[0]==='auth') process.exit(0);
if(args[0]==='get' && args[1]?.startsWith('serviceaccount/')) { console.log(JSON.stringify({metadata:{labels:{'oke-llm/storage-owner':owner}}})); process.exit(0); }
if(args[0]==='get' && args[1]?.startsWith('pvc/')) { console.log(JSON.stringify({metadata:{labels:{'oke-llm/storage-owner':owner}},spec:{storageClassName:'oci-bv',accessModes:['ReadWriteOnce'],resources:{requests:{storage:'64Gi'}}},status:{phase:fs.existsSync(path.join(root,'job-created'))&&!process.env.MOCK_PVC_NEVER_BINDS?'Bound':'Pending'}})); process.exit(0); }
if(args[0]==='get' && args[1]==='storageclass') { console.log(JSON.stringify({volumeBindingMode:process.env.MOCK_IMMEDIATE_STORAGECLASS?'Immediate':'WaitForFirstConsumer'})); process.exit(0); }
if(args[0]==='get' && args[1]==='nodes') { console.log(JSON.stringify({items:[{metadata:{labels:{'node-pool':'cpu'}},spec:{},status:{conditions:[{type:'Ready',status:'True'}],allocatable:{'nvidia.com/gpu':process.env.MOCK_GPU_NODE?'4':'0'}}}]})); process.exit(0); }
if(args[0]==='create' && args[1]==='configmap') process.exit(0);
if(args[0]==='create' && args[1]==='-f') { if(process.env.MOCK_JOB_CONFLICT) process.exit(96); fs.writeFileSync(path.join(root,'job-created'),'yes'); process.exit(0); }
if(args[0]==='get' && args[1]==='job') { console.log(JSON.stringify({status:{succeeded:1}})); process.exit(0); }
if(args[0]==='logs' || args[0]==='delete') process.exit(0);
process.exit(99);
`;
function runController(t, extraEnv = {}) {
  const f = fixture(t);
  for (const script of ['stage.sh', 'download.sh', 'job.jq']) copyFileSync(join(moduleDir, 'scripts', script), join(f.root, 'input', script));
  writeFileSync(join(f.root, 'input', 'model.json'), JSON.stringify(f.config));
  writeFileSync(join(f.root, 'bin', 'cat'), String.raw`#!/usr/bin/env node
const fs=require('node:fs'); for(const file of process.argv.slice(2)) process.stdout.write(file==='/proc/sys/kernel/random/uuid'?'test-unique-run':fs.readFileSync(file));
`, { mode: 0o755 });
  writeFileSync(join(f.root, 'bin', 'curl'), String.raw`#!/usr/bin/env node
const fs=require('node:fs'),crypto=require('node:crypto'); const args=process.argv.slice(2),out=args[args.indexOf('-o')+1],source=fs.readFileSync(process.env.MOCK_KUBECTL);
fs.writeFileSync(out,args.some(x=>x.endsWith('/kubectl.sha256'))?crypto.createHash('sha256').update(source).digest('hex'):source);
`, { mode: 0o755 });
  const kubectlSource = join(f.root, 'kubectl-source');
  writeFileSync(kubectlSource, kubectlMock);
  writeFileSync(join(f.root, 'bin', 'oci'), String.raw`#!/usr/bin/env node
const fs=require('node:fs'),path=require('node:path'),args=process.argv.slice(2);
if(process.env.OCI_CLI_AUTH!=='resource_principal') process.exit(91);
if(args.slice(0,3).join(' ')==='ce cluster create-kubeconfig') process.exit(0);
if(args.slice(0,4).join(' ')==='artifacts generic artifact upload-by-path') {
  const body=args[args.indexOf('--content-body')+1];
  if(body.startsWith('file://')) process.exit(92);
  fs.copyFileSync(body,path.join(process.env.MOCK_OS_DIR,'report.json')); console.log('{}'); process.exit(0);
} process.exit(99);
`, { mode: 0o755 });
  const result = spawnSync('bash', [join(f.root, 'input', 'stage.sh')], { encoding: 'utf8', env: {
    ...process.env, PATH: `${join(f.root, 'bin')}:${process.env.PATH}`, MOCK_OS_DIR: join(f.root, 'objects'), MOCK_KUBECTL: kubectlSource,
    MODEL_CONFIG_SHA256: hash(JSON.stringify(f.config)), MODEL_STAGE_NAME: 'fixture', STAGING_IMAGE: `image@sha256:${'d'.repeat(64)}`,
    JOB_DEADLINE_SECONDS: '300', CLUSTER_ID: 'cluster', KUBERNETES_VERSION: 'v1.34.1', RESULT_REPOSITORY_ID: 'results', OCI_CLI_REGION: 'eu-frankfurt-1', ...extraEnv
  }});
  const calls = readFileSync(join(f.root, 'objects', 'kubectl-calls'), 'utf8').trim().split('\n').map(JSON.parse);
  const report = JSON.parse(readFileSync(join(f.root, 'objects', 'report.json'), 'utf8'));
  return { result, calls, report };
}

test('controller stages only a Job and cleans transient resources while retaining PVC and namespace', t => {
  const { result, calls, report } = runController(t);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(report.status, 'staged');
  assert.equal(calls.some(args => args[0] === 'create' && args[1] === '-f'), true);
  const deletes = calls.filter(args => !args.includes('auth') && args.includes('delete'));
  assert.equal(deletes.length, 2);
  assert.equal(deletes.every(args => args.includes('job') || args.includes('configmap')), true);
});

test('concurrent Job conflict never deletes the other execution Job', t => {
  const { result, calls, report } = runController(t, { MOCK_JOB_CONFLICT: 'true' });
  assert.notEqual(result.status, 0);
  assert.equal(report.status, 'failed');
  assert.equal(calls.some(args => !args.includes('auth') && args.includes('delete') && args.includes('job')), false);
  assert.equal(calls.some(args => !args.includes('auth') && args.includes('delete') && args.includes('configmap')), true);
});

test('foreign PVC ownership and GPU nodes fail preflight before any Job creation', t => {
  for (const extraEnv of [{ MOCK_FOREIGN_PVC: 'true' }, { MOCK_GPU_NODE: 'true' }]) {
    const { result, calls, report } = runController(t, extraEnv);
    assert.notEqual(result.status, 0);
    assert.equal(report.status, 'failed');
    assert.equal(calls.some(args => !args.includes('auth') && args.includes('create')), false);
  }
});

test('Pending WFFC volume binds through first Job; other pending claims and missing final binding fail', t => {
  const immediate = runController(t, { MOCK_IMMEDIATE_STORAGECLASS: 'true' });
  assert.notEqual(immediate.result.status, 0);
  assert.equal(immediate.calls.some(args => !args.includes('auth') && args.includes('create')), false);
  const unbound = runController(t, { MOCK_PVC_NEVER_BINDS: 'true' });
  assert.notEqual(unbound.result.status, 0);
  assert.match(unbound.result.stderr, /no owned Bound PVC/);
  assert.equal(unbound.report.status, 'failed');
});
