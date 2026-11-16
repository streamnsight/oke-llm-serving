// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const script = resolve(import.meta.dirname, '../repair-root-filesystem.sh');
const instance = 'ocid1.instance.oc1.test.exact-instance';
const bytes = 204 * 1024 ** 3;
function runHost(t, args = [], env = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'root-filesystem-test-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const mocks = `
id() { echo "\${MOCK_UID:-0}"; }
curl() { printf '{"id":"%s"}\\n' "\${MOCK_INSTANCE:-$EXPECTED_INSTANCE}"; }
findmnt() { if [[ $* == *FSTYPE* ]]; then echo "\${MOCK_FSTYPE:-xfs}"; else echo /dev/mapper/ocivolume-root; fi; }
lsblk() { printf '{"blockdevices":[{"name":"/dev/sda","type":"disk","size":%s}]}\\n' "\${MOCK_DISK_BYTES:-$EXPECTED_BYTES}"; }
df() { if [[ $* == *--output=size* ]]; then if [[ -f $MOCK_DIR/grew ]]; then echo 190000000000; else echo 31600000000; fi; else echo 'root filesystem geometry'; fi; }
systemctl() { printf 'systemctl %s\\n' "$*" >> "$MOCK_DIR/calls"; echo active; }
function /usr/libexec/oci-growfs() {
  printf 'growfs %s\\n' "$*" >> "$MOCK_DIR/calls"
  if [[ $* == -y && \${MOCK_NO_GROWTH:-false} != true ]]; then : > "$MOCK_DIR/grew"; fi
}
`;
  writeFileSync(join(dir, 'mocks.sh'), mocks);
  writeFileSync(join(dir, 'calls'), '');
  const result = spawnSync('bash', [script, instance, String(bytes), ...args], {
    encoding: 'utf8', env: { ...process.env, BASH_ENV: join(dir, 'mocks.sh'), MOCK_DIR: dir, EXPECTED_INSTANCE: instance, EXPECTED_BYTES: String(bytes), ...env }
  });
  return { ...result, calls: readFileSync(join(dir, 'calls'), 'utf8').trim().split('\n').filter(Boolean) };
}

test('default host inspection invokes only the Oracle no-expansion preview and never restarts kubelet', t => {
  const result = runHost(t);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(result.calls, ['systemctl is-active kubelet.service', 'growfs -n']);
  assert.match(result.stdout, /Inspection complete/);
});
test('explicit apply grows before restarting kubelet and verifies actual filesystem growth', t => {
  const result = runHost(t, ['--apply']);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(result.calls, ['systemctl is-active kubelet.service', 'growfs -n', 'growfs -y', 'systemctl restart kubelet.service', 'systemctl is-active kubelet.service']);
  const unchanged = runHost(t, ['--apply'], { MOCK_NO_GROWTH: 'true' });
  assert.equal(unchanged.status, 2);
  assert.match(unchanged.stderr, /did not increase/);
  assert(!unchanged.calls.some(call => call.includes('restart')));
});
test('foreign instance, insufficient disk, unsupported filesystem and absent root access fail before growfs', t => {
  for (const env of [{ MOCK_INSTANCE: 'ocid1.instance.oc1.test.foreign' }, { MOCK_DISK_BYTES: String(50 * 1024 ** 3) }, { MOCK_FSTYPE: 'overlay' }, { MOCK_UID: '1000' }]) {
    const result = runHost(t, [], env);
    assert.equal(result.status, 2, result.stderr);
    assert.equal(result.calls.length, 0);
  }
});

test('renderer validates actual boot size and ownership using reads, and never submits its native command', t => {
  const dir = mkdtempSync(join(tmpdir(), 'root-repair-render-test-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const cluster = 'ocid1.cluster.oc1.test.cluster', pool = 'ocid1.nodepool.oc1.test.pool', platform = 'fixture', node = '10.0.0.1';
  const owner = createHash('sha256').update(`${platform}/${cluster}`).digest('hex').slice(0, 32);
  const docs = {
    namespace: { metadata: { annotations: { 'oke-llm/platform-name': platform, 'oke-llm/cluster-id': cluster }, labels: { 'oke-llm/platform-owner': owner, 'oke-llm/model-namespace': 'true' } } },
    node: { metadata: { name: node, uid: 'exact-node-uid', labels: { 'oke-llm/allocation': platform, 'node.kubernetes.io/instance-type': 'BM.GPU.A10.4' } }, spec: { providerID: instance }, status: { allocatable: { 'nvidia.com/gpu': '4' }, conditions: [{ type: 'Ready', status: 'True' }] } },
    pool: { data: { 'cluster-id': cluster, 'lifecycle-state': 'ACTIVE', 'node-shape': 'BM.GPU.A10.4', nodes: [{ id: instance, 'lifecycle-state': 'ACTIVE' }], 'initial-node-labels': [{ key: 'oke-llm/allocation', value: platform }], 'freeform-tags': { 'oke-llm-allocation': 'exact-owner' }, 'node-source-details': { 'boot-volume-size-in-gbs': 204 } } },
    instance: { data: { id: instance, 'lifecycle-state': 'RUNNING', shape: 'BM.GPU.A10.4', 'compartment-id': 'compartment', 'availability-domain': 'AD' } },
    attachments: { data: [{ 'instance-id': instance, 'lifecycle-state': 'ATTACHED', 'boot-volume-id': 'boot' }] },
    boot: { data: { id: 'boot', 'lifecycle-state': 'AVAILABLE', 'size-in-gbs': 204 } },
    plugins: { data: [{ name: 'Compute Instance Run Command', status: 'RUNNING' }] }, pods: { items: [] }
  };
  for (const [name, value] of Object.entries(docs)) writeFileSync(join(dir, `${name}.json`), JSON.stringify(value));
  writeFileSync(join(dir, 'calls'), '');
  writeFileSync(join(dir, 'mocks.sh'), `
kubectl() { printf 'kubectl %s\\n' "$*" >> "$MOCK_DIR/calls"; case "$1 $2" in 'get namespace') cat "$MOCK_DIR/namespace.json";; 'get node') cat "$MOCK_DIR/node.json";; 'get pods') cat "$MOCK_DIR/pods.json";; *) return 97;; esac; }
oci() { printf 'oci %s\\n' "$*" >> "$MOCK_DIR/calls"; case "$1 $2 $3" in 'ce node-pool get') cat "$MOCK_DIR/pool.json";; 'compute instance get') cat "$MOCK_DIR/instance.json";; 'compute boot-volume-attachment list') cat "$MOCK_DIR/attachments.json";; 'bv boot-volume get') cat "$MOCK_DIR/boot.json";; 'instance-agent plugin list') cat "$MOCK_DIR/plugins.json";; *) return 97;; esac; }
`);
  const run = (...flags) => spawnSync('bash', [resolve(import.meta.dirname, '../render-root-repair-command.sh'), cluster, pool, node, 'fixture-model-one', ...flags], { encoding: 'utf8', env: { ...process.env, MOCK_DIR: dir, BASH_ENV: join(dir, 'mocks.sh') } });
  let result = run();
  assert.equal(result.status, 0, result.stderr);
  const payload = JSON.parse(result.stdout);
  assert.equal(payload.target.instanceId, instance);
  assert.match(payload.content.source.text, /sudo -n/);
  assert(payload.content.source.text.includes(`'${bytes}' 'inspect'`));
  assert.match(result.stderr, /No command submitted/);
  assert(!readFileSync(join(dir, 'calls'), 'utf8').match(/\b(create|update|delete|restart)\b/));
  result = run('--pod');
  assert.equal(result.status, 0, result.stderr);
  const pod = JSON.parse(result.stdout);
  assert.equal(pod.spec.nodeName, node); assert.equal(pod.metadata.namespace, 'kube-system');
  assert.equal(pod.spec.hostPID, true); assert.equal(pod.spec.hostNetwork, true);
  assert.equal(pod.spec.automountServiceAccountToken, false); assert.equal(pod.spec.restartPolicy, 'Never');
  assert(pod.spec.activeDeadlineSeconds <= 600); assert(pod.spec.containers[0].image.includes('@sha256:'));
  assert(!JSON.stringify(pod.spec.containers[0].resources).includes('nvidia.com/gpu'));
  assert(pod.spec.containers[0].args[0].includes('--target 1 --mount --pid --net --root --wd'));
  assert(pod.spec.containers[0].args[0].includes(`'${bytes}' 'inspect'`));
  assert.equal(spawnSync('bash', ['-n'], { input: pod.spec.containers[0].args[0] }).status, 0);
  result = run('--pod', '--apply');
  assert.equal(result.status, 0, result.stderr);
  assert(JSON.parse(result.stdout).spec.containers[0].args[0].includes(`'${bytes}' '--apply'`));
  writeFileSync(join(dir, 'pods.json'), JSON.stringify({ items: [{ status: { phase: 'Running' }, metadata: { ownerReferences: [{ kind: 'ReplicaSet' }] } }] }));
  result = run('--pod', '--apply');
  assert.equal(result.status, 2); assert.match(result.stderr, /Active non-DaemonSet workloads/);
  writeFileSync(join(dir, 'pods.json'), JSON.stringify(docs.pods));
  docs.boot.data['size-in-gbs'] = 50;
  writeFileSync(join(dir, 'boot.json'), JSON.stringify(docs.boot));
  result = run();
  assert.equal(result.status, 2);
  assert.match(result.stderr, /Actual attached boot volume is smaller/);
  assert.equal(result.stdout, '');
  writeFileSync(join(dir, 'boot.json'), JSON.stringify({ data: { id: 'boot', 'lifecycle-state': 'AVAILABLE', 'size-in-gbs': 204 } }));
  docs.pool.data['cluster-id'] = 'foreign-cluster';
  writeFileSync(join(dir, 'pool.json'), JSON.stringify(docs.pool));
  result = run();
  assert.equal(result.status, 2);
  assert.match(result.stderr, /exact active cluster\/instance\/allocation/);
});
