// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, readdirSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const moduleDir = resolve(fileURLToPath(new URL('..', import.meta.url)));
const hash = value => createHash('sha256').update(value).digest('hex');
const namespace = 'platform-model-example';
const pipelines = ['ocid1.devopsdeploypipeline.oc1.fixtureone', 'ocid1.devopsdeploypipeline.oc1.fixturetwo'];
const kubectl = String.raw`#!/usr/bin/env node
const fs=require('node:fs'),path=require('node:path');
const args=process.argv.slice(2),root=process.env.MOCK_DIR, ns=args.includes('-n')?args[args.indexOf('-n')+1]:'';
const singular=s=>({namespaces:'namespace',leases:'lease',pods:'pod'}[s.toLowerCase()]||s.toLowerCase());
const key=(kind,name,namespace='')=>path.join(root,'objects',Buffer.from([singular(kind),namespace,name].join('/')).toString('hex')+'.json');
fs.appendFileSync(path.join(root,'calls'),JSON.stringify(args)+'\n');
if(args[0]==='create'||args[0]==='replace') {
  const doc=JSON.parse(fs.readFileSync(args[args.indexOf('-f')+1],'utf8')),file=key(doc.kind,doc.metadata.name,doc.metadata.namespace||'');
  if(args[0]==='create'&&fs.existsSync(file)) process.exit(90);
  if(args[0]==='replace'&&(!fs.existsSync(file)||JSON.parse(fs.readFileSync(file)).metadata.resourceVersion!==doc.metadata.resourceVersion)) process.exit(91);
  doc.metadata.resourceVersion=String(Number(doc.metadata.resourceVersion||'0')+1); fs.writeFileSync(file,JSON.stringify(doc)); console.log('{}'); process.exit(0);
}
if(args[0]==='get') {
  if(singular(args[1])==='pod') { console.log(JSON.stringify({items:process.env.MOCK_ACTIVE_POD?[{status:{phase:'Running'}}]:[]})); process.exit(0); }
  if(args[1].toLowerCase()==='rolebindings'&&args.includes('--all-namespaces')) { console.log(JSON.stringify({items:fs.readdirSync(path.join(root,'objects')).map(name=>JSON.parse(fs.readFileSync(path.join(root,'objects',name)))).filter(doc=>doc.kind==='RoleBinding')})); process.exit(0); }
  const file=key(args[1],args[2],ns);
  if(fs.existsSync(file)) { console.log(fs.readFileSync(file,'utf8')); process.exit(0); }
  if(args.includes('--ignore-not-found')) process.exit(0);
  process.exit(92);
}
if(args[0]==='delete') { const file=key(args[1],args[2],ns); if(fs.existsSync(file)) fs.unlinkSync(file); process.exit(0); }
process.exit(99);
`;
function setup(t, components = {}) {
  const root = mkdtempSync(join(tmpdir(), 'model-onboarding-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  for (const name of ['bin', 'input', 'objects']) mkdirSync(join(root, name));
  for (const name of ['onboard-model.sh', 'model-access.jq']) copyFileSync(join(moduleDir, 'scripts', name), join(root, 'input', name));
  writeFileSync(join(root, 'input', 'model-access-context.json'), JSON.stringify({ components: Object.fromEntries(Object.entries(components).map(([name,c])=>[name,{ownership_token:hash(`platform/cluster/${name}`),release_name:name,crd_names:[],...c}])) }));
  writeFileSync(join(root, 'kubectl'), kubectl);
  const scripts = {
    cat: String.raw`#!/usr/bin/env node
const fs=require('node:fs'); for(const name of process.argv.slice(2)) process.stdout.write(name==='/proc/sys/kernel/random/uuid'?'execution-fixture':fs.readFileSync(name));
`,
    curl: String.raw`#!/usr/bin/env node
const fs=require('node:fs'),crypto=require('node:crypto'),args=process.argv.slice(2),source=fs.readFileSync(process.env.MOCK_KUBECTL);
fs.writeFileSync(args[args.indexOf('-o')+1],args.some(a=>a.endsWith('/kubectl.sha256'))?crypto.createHash('sha256').update(source).digest('hex'):source);
`,
    oci: String.raw`#!/usr/bin/env node
const fs=require('node:fs'),path=require('node:path'),args=process.argv.slice(2);
fs.appendFileSync(path.join(process.env.MOCK_DIR,'oci-calls'),JSON.stringify(args)+'\n');
if(process.env.OCI_CLI_AUTH!=='resource_principal') process.exit(93);
if(args.slice(0,3).join(' ')==='devops project get') { console.log(JSON.stringify({data:{id:process.env.MODEL_PROJECT_ID,'lifecycle-state':process.env.MOCK_INACTIVE_PROJECT?'DELETED':'ACTIVE'}})); process.exit(0); }
if(args.slice(0,3).join(' ')==='devops deploy-pipeline get') {
 const id=args[args.indexOf('--pipeline-id')+1]; console.log(JSON.stringify({data:{id,'project-id':process.env.MOCK_FOREIGN_PROJECT?'foreign-project':process.env.MODEL_PROJECT_ID,'lifecycle-state':process.env.MOCK_INACTIVE_PIPELINE?'DELETED':'ACTIVE','deploy-pipeline-parameters':{items:[{name:'MODEL_NAMESPACE','default-value':process.env.MOCK_WRONG_NAMESPACE?'foreign':process.env.MODEL_NAMESPACE},{name:'MODEL_PROJECT_ID','default-value':process.env.MODEL_PROJECT_ID},{name:'MODEL_CLUSTER_ID','default-value':process.env.MOCK_WRONG_CLUSTER?'foreign':process.env.CLUSTER_ID},{name:'MODEL_PLATFORM_NAME','default-value':process.env.MOCK_WRONG_PLATFORM?'foreign':process.env.PLATFORM_NAME},{name:'MODEL_GPU_POOL_ID','default-value':process.env.MOCK_WRONG_POOL?'foreign':process.env.MODEL_GPU_POOL_ID}]}}})); process.exit(0);
}
if(args.slice(0,3).join(' ')==='ce cluster create-kubeconfig') process.exit(0);
process.exit(99);
`
  };
  for (const [name, body] of Object.entries(scripts)) writeFileSync(join(root, 'bin', name), body, { mode: 0o755 });
  const objects = () => readdirSync(join(root, 'objects')).map(name => JSON.parse(readFileSync(join(root, 'objects', name), 'utf8')));
  const calls = () => existsSync(join(root, 'calls')) ? readFileSync(join(root, 'calls'), 'utf8').trim().split('\n').map(JSON.parse) : [];
  function run(env = {}) {
    return spawnSync('bash', [join(root, 'input', 'onboard-model.sh')], { encoding: 'utf8', env: {
      ...process.env, PATH: `${join(root, 'bin')}:${process.env.PATH}`, MOCK_DIR: root, MOCK_KUBECTL: join(root, 'kubectl'),
      PLATFORM_NAME: 'platform', CLUSTER_ID: 'cluster', PROJECT_ID: 'platform-project', MODEL_PROJECT_ID: 'ocid1.devopsproject.oc1.model', MODEL_GPU_POOL_ID: 'runtime', MODEL_NAMESPACE: namespace, MODEL_PIPELINE_IDS: pipelines.join(','), MODEL_ACCESS_OPERATION: 'grant',
      KUBERNETES_VERSION: 'v1.34.1', OCI_CLI_REGION: 'eu-frankfurt-1', ...env
    }});
  }
  const ociCalls = () => existsSync(join(root, 'oci-calls')) ? readFileSync(join(root, 'oci-calls'), 'utf8').trim().split('\n').map(JSON.parse) : [];
  return { root, run, objects, calls, ociCalls };
}

test('trusted onboarding grants only exact namespace access and read-only cluster discovery; repeat is safe', t => {
  const f = setup(t);
  let result = f.run();
  assert.equal(result.status, 0, result.stderr);
  const report = JSON.parse(result.stdout.slice(result.stdout.lastIndexOf('\n{') + 1));
  assert.equal(report.status, 'passed'); assert.equal(report.exit_code, 0);
  assert.deepEqual(report.pipeline_ids, pipelines);
  const docs = f.objects(), ns = docs.find(o => o.kind === 'Namespace');
  assert.equal(ns.metadata.labels['oke-llm/platform-owner'], hash('platform/cluster').slice(0, 32));
  assert.equal(docs.filter(o => o.kind === 'RoleBinding' && o.metadata.namespace === namespace && o.subjects[0].kind === 'User').length, 2);
  assert.deepEqual(docs.filter(o => o.kind === 'RoleBinding' && o.metadata.namespace === namespace && o.subjects[0].kind === 'User').map(o => o.subjects[0].name).sort(), [...pipelines].sort());
  assert.equal(docs.some(o => o.kind === 'ServiceAccount' && o.metadata.name === 'oke-llm-router'), true);
  const reader = docs.find(o => o.kind === 'ClusterRole');
  assert.equal(reader.rules.every(rule => rule.verbs.every(v => ['get', 'list', 'watch'].includes(v))), true);
  assert.equal(docs.some(o => o.roleRef?.name === 'cluster-admin'), false);
  assert.equal(docs.some(o => ['Pod', 'Deployment', 'StatefulSet', 'Job'].includes(o.kind)), false);
  result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(f.objects().filter(o => o.kind === 'Namespace').length, 1);
});

test('pipeline CSV rejects empty, malformed, duplicate and oversized lists before any OCI or Kubernetes call', t => {
  const inputs = ['', ',', `${pipelines[0]},`, `,${pipelines[0]}`, `${pipelines[0]},,${pipelines[1]}`, `${pipelines[0]}, ${pipelines[1]}`, `${pipelines[0]},${pipelines[0]}`, 'not-an-ocid', 'ocid1.devopsproject.oc1.wrongtype', JSON.stringify(pipelines), Array.from({ length: 17 }, (_, i) => `ocid1.devopsdeploypipeline.oc1.fixture${i}`).join(',')];
  for (const value of inputs) {
    const f = setup(t), result = f.run({ MODEL_PIPELINE_IDS: value });
    assert.equal(result.status, 2, `${value}: ${result.stderr}`);
    assert.match(result.stderr, /MODEL_PIPELINE_IDS.*1 to 16 unique exact/);
    assert.deepEqual(f.objects(), []); assert.deepEqual(f.calls(), []); assert.deepEqual(f.ociCalls(), []);
  }
  const f = setup(t), unexpected = join(f.root, 'unexpected');
  const result = f.run({ MODEL_PIPELINE_IDS: `$(touch ${unexpected})` });
  assert.equal(result.status, 2); assert.equal(existsSync(unexpected), false); assert.deepEqual(f.ociCalls(), []);
});

test('wrong model project/cluster/platform/pool/namespace and inactive principals are rejected before Kubernetes mutation', t => {
  for (const env of [{ MOCK_FOREIGN_PROJECT: 'true' }, { MOCK_WRONG_NAMESPACE: 'true' }, { MOCK_WRONG_CLUSTER: 'true' }, { MOCK_WRONG_PLATFORM: 'true' }, { MOCK_WRONG_POOL: 'true' }, { MOCK_INACTIVE_PROJECT: 'true' }, { MOCK_INACTIVE_PIPELINE: 'true' }]) {
    const f = setup(t), result = f.run(env);
    assert.notEqual(result.status, 0);
    assert.deepEqual(f.objects(), []);
    assert.equal(f.calls().length, 0);
  }
});

test('a pre-existing foreign namespace is never adopted', t => {
  const f = setup(t), key = Buffer.from(['namespace', '', namespace].join('/')).toString('hex');
  writeFileSync(join(f.root, 'objects', `${key}.json`), JSON.stringify({ kind: 'Namespace', metadata: { name: namespace, labels: {} } }));
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.equal(f.calls().some(args => ['create', 'replace', 'delete'].includes(args[0])), false);
});

test('revoke refuses active workloads, then removes only the exact requested principal bindings', t => {
  const f = setup(t);
  assert.equal(f.run().status, 0);
  let result = f.run({ MODEL_ACCESS_OPERATION: 'revoke', MOCK_ACTIVE_POD: 'true' });
  assert.notEqual(result.status, 0);
  assert.equal(f.objects().filter(o => o.kind === 'RoleBinding' && o.metadata.namespace === namespace && o.subjects[0].kind === 'User').length, 2);
  result = f.run({ MODEL_ACCESS_OPERATION: 'revoke', MODEL_PIPELINE_IDS: pipelines[0], MOCK_INACTIVE_PROJECT: 'true', MOCK_INACTIVE_PIPELINE: 'true' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(f.objects().filter(o => o.kind === 'RoleBinding' && o.metadata.namespace === namespace && o.subjects[0].kind === 'User').length, 1);
  assert.equal(f.objects().some(o => o.kind === 'Namespace'), true);
  assert.equal(f.calls().some(args => args[0] === 'delete' && args[1] === 'namespace'), false);
});

test('an orphaned onboarding lease is not stolen or deleted', t => {
  const f = setup(t);
  assert.equal(f.run().status, 0);
  const key = Buffer.from(['lease', namespace, 'oke-llm-model-onboarding'].join('/')).toString('hex');
  writeFileSync(join(f.root, 'objects', `${key}.json`), JSON.stringify({ kind: 'Lease', metadata: { name: 'oke-llm-model-onboarding', namespace }, spec: { holderIdentity: 'another-execution' } }));
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.equal(f.objects().find(o => o.kind === 'Lease').spec.holderIdentity, 'another-execution');
});

test('shared readiness access is exact-name read-only and revoke cleans bindings after a component is removed', t => {
  const f = setup(t, { prometheus: { namespace: 'monitoring', mode: 'managed', owner_name: 'prometheus-owned-status', deployment_names: ['prometheus-operator'] } });
  let result = f.run();
  assert.equal(result.status, 0, result.stderr);
  const role = f.objects().find(doc => doc.kind === 'Role' && doc.metadata.namespace === 'monitoring');
  assert.equal(role.rules.every(rule => JSON.stringify(rule.verbs) === '["get"]'), true);
  assert.deepEqual(role.rules.find(rule => rule.resources[0] === 'configmaps').resourceNames, ['prometheus-owned-status']);
  assert.deepEqual(role.rules.find(rule => rule.resources[0] === 'deployments').resourceNames, ['prometheus-operator']);
  writeFileSync(join(f.root, 'input', 'model-access-context.json'), JSON.stringify({ components: {} }));
  result = f.run({ MODEL_ACCESS_OPERATION: 'revoke' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(f.objects().filter(doc => doc.kind === 'RoleBinding' && doc.subjects[0].kind === 'User').length, 0);
  assert.equal(f.objects().some(doc => doc.kind === 'Role' && doc.metadata.namespace === 'monitoring'), true, 'retained read role cannot affect other workloads');
});


test('model runtime context is in trusted kube-system with only exact-name model read access', t => {
  const f = setup(t);
  const r = f.run(); assert.equal(r.status, 0, r.stderr);
  const context = f.objects().find(d => d.kind === 'ConfigMap');
  assert.equal(context.metadata.namespace, 'kube-system');
  const data = JSON.parse(context.data['context.json']);
  assert.equal(data.model_project_id, 'ocid1.devopsproject.oc1.model');
  assert.equal(data.gpu_pool_id, 'runtime');
  const role = f.objects().find(d => d.kind === 'Role' && d.metadata.namespace === 'kube-system');
  assert.deepEqual(role.rules, [{apiGroups:[''],resources:['configmaps'],resourceNames:[context.metadata.name],verbs:['get']}]);
  const reader = f.objects().find(d => d.kind === 'ClusterRole');
  assert.equal(reader.rules.some(rule => rule.resources?.includes('pods')), false, 'no cross-namespace Pod-spec access');
});
