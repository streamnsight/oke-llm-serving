// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
const script = resolve('modules/cluster-add-ons/oke-managed-addons/scripts/ensure-addons.sh');
const addon = (name, state = 'ACTIVE', configurations = []) => ({ 'addon-name': name, 'lifecycle-state': state, configurations });
const supported = ['NodeFeatureDiscovery', 'NvidiaGpuOperator', 'NvidiaNetworkOperator', 'GpuHealthMonitoring'];
function fixture(inventory, options = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'oke-addons-'));
  const state = join(dir, 'state.json');
  writeFileSync(state, JSON.stringify({ inventory, calls: [], ...options }));
  writeFileSync(join(dir, 'sleep'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
  writeFileSync(join(dir, 'oci'), `#!${process.execPath}
const fs = require('node:fs');
const file = process.env.FIXTURE_STATE;
const s = JSON.parse(fs.readFileSync(file, 'utf8'));
const args = process.argv.slice(2);
const at = args.indexOf('ce');
const cmd = args.slice(at, at + 3).join(' ');
const value = name => args[args.indexOf(name) + 1];
if (value('--cluster-id') !== 'fixture-cluster') process.exit(97);
s.calls.push(args);
if (s.deny) { fs.writeFileSync(file, JSON.stringify(s)); process.stderr.write('NotAuthorized'); process.exit(1); }
if (cmd === 'ce addon list') {
  if (s.transition) { for (const a of s.inventory) if (a['lifecycle-state'] === 'UPDATING') a['lifecycle-state'] = 'ACTIVE'; }
  fs.writeFileSync(file, JSON.stringify(s));
  process.stdout.write(JSON.stringify({ data: { items: s.inventory } }));
} else if (cmd === 'ce addon install') {
  if (value('--is-override-existing') !== 'false') process.exit(98);
  const name = value('--addon-name');
  if (s.inventory.some(a => a['addon-name'] === name && a['lifecycle-state'] !== 'DELETED')) process.exit(99);
  s.inventory = s.inventory.filter(a => a['addon-name'] !== name);
  s.inventory.push({ 'addon-name': name, 'lifecycle-state': s.failedInstall ? 'NEEDS_ATTENTION' : 'ACTIVE', configurations: [] });
  fs.writeFileSync(file, JSON.stringify(s)); process.stdout.write('{}');
} else { process.stderr.write('Unexpected CLI mutation'); process.exit(97); }
`, { mode: 0o755 });
  return {
    run(extra = {}) { return spawnSync('bash', [script], { encoding: 'utf8', env: {
      ...process.env, PATH: `${dir}:${process.env.PATH}`, FIXTURE_STATE: state,
      CLUSTER_ID: 'fixture-cluster', REGION: 'fixture-region', REQUIRES_RDMA: 'false', INSTALL_GPU_HEALTH: 'true',
      SUPPORTED_ADDONS_JSON: JSON.stringify(supported), TF_VAR_auth: '', OCI_AUTH: '', OCI_RESOURCE_PRINCIPAL_VERSION: '', ...extra,
    } }); },
    state: () => JSON.parse(readFileSync(state)),
    close: () => rmSync(dir, { recursive: true, force: true }),
  };
}
const installs = state => state.calls.filter(args => args.includes('install')).map(args => args[args.indexOf('--addon-name') + 1]);
test('enables dependencies in order, adds RDMA only when requested, reruns without installing again', () => {
  const f = fixture([]);
  try {
    let result = f.run({ REQUIRES_RDMA: 'true' }); assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(installs(f.state()), supported);
    result = f.run({ REQUIRES_RDMA: 'true' }); assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(installs(f.state()), supported);
  } finally { f.close(); }
});
test('preserves an existing standalone GPU plugin and its configuration', () => {
  const plugin = addon('NvidiaDevicePlugin', 'ACTIVE', [{ key: 'custom', value: 'keep' }]);
  const f = fixture([addon('NodeFeatureDiscovery'), plugin]);
  try {
    const result = f.run({ INSTALL_GPU_HEALTH: 'false' }); assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(installs(f.state()), []); assert.deepEqual(f.state().inventory[1], plugin);
  } finally { f.close(); }
});
test('uses the compatible standalone GPU plugin when the Operator is unavailable', () => {
  const f = fixture([]);
  try {
    const result = f.run({ INSTALL_GPU_HEALTH: 'false', SUPPORTED_ADDONS_JSON: JSON.stringify(['NodeFeatureDiscovery', 'NvidiaDevicePlugin']) });
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(installs(f.state()), ['NodeFeatureDiscovery', 'NvidiaDevicePlugin']);
  } finally { f.close(); }
});
test('does not override an Operator with an explicitly disabled device plugin', () => {
  const f = fixture([addon('NodeFeatureDiscovery'), addon('NvidiaGpuOperator', 'ACTIVE', [{ key: 'devicePlugin.enabled', value: 'false' }])]);
  try { const result = f.run(); assert.notEqual(result.status, 0); assert.match(result.stderr, /disabled settings were preserved/); assert.deepEqual(installs(f.state()), []); }
  finally { f.close(); }
});
test('allows an intentionally disabled Operator device plugin alongside the standalone plugin', () => {
  const f = fixture([addon('NodeFeatureDiscovery'), addon('NvidiaGpuOperator', 'ACTIVE', [{ key: 'devicePlugin.enabled', value: 'false' }]), addon('NvidiaDevicePlugin')]);
  try { const result = f.run({ INSTALL_GPU_HEALTH: 'false' }); assert.equal(result.status, 0, result.stderr); assert.deepEqual(installs(f.state()), []); }
  finally { f.close(); }
});
test('stops on failed installs and never overrides or allocates a GPU', () => {
  const f = fixture([], { failedInstall: true });
  try { const result = f.run(); assert.notEqual(result.status, 0); assert.match(result.stderr, /NEEDS_ATTENTION/); assert.deepEqual(installs(f.state()), ['NodeFeatureDiscovery']); }
  finally { f.close(); }
});
test('waits for an in-progress installation rather than starting another', () => {
  const f = fixture([addon('NodeFeatureDiscovery', 'UPDATING'), addon('NvidiaGpuOperator')], { transition: true });
  try { const result = f.run({ INSTALL_GPU_HEALTH: 'false' }); assert.equal(result.status, 0, result.stderr); assert.deepEqual(installs(f.state()), []); }
  finally { f.close(); }
});
test('fails closed on denied inventory and unsupported required add-ons', () => {
  for (const denied of [true, false]) {
    const f = fixture([], { deny: denied });
    try { const result = f.run({ SUPPORTED_ADDONS_JSON: '[]' }); assert.notEqual(result.status, 0); assert.deepEqual(installs(f.state()), []); }
    finally { f.close(); }
  }
});
