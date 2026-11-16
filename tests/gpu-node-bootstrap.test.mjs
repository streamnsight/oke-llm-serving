// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

const source = readFileSync(new URL('../modules/infrastructure/gpu-allocation/cloud-init/gpu-node.sh', import.meta.url), 'utf8');

function fixture(overrides = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), 'oke-gpu-bootstrap-'));
  const bin = path.join(dir, 'bin');
  mkdirSync(bin);
  const trace = path.join(dir, 'trace');
  const bootstrap = path.join(dir, 'oke-init.sh');
  const canonical = path.join(dir, 'canonical-init.sh');
  const script = path.join(dir, 'gpu-node.sh');
  // Relocate only the fixed output file so this test cannot write host /var/run.
  writeFileSync(script, source.replaceAll('/var/run/oke-init.sh', bootstrap));
  writeFileSync(canonical, '#!/bin/bash\nprintf "%s\\n" oke-init >> "$TRACE"\nexit "${MOCK_INIT_EXIT:-0}"\n');
  writeFileSync(path.join(bin, 'curl'), `#!/bin/bash
set -euo pipefail
printf '%s\\n' metadata >> "$TRACE"
printf '%s\\n' "$@" > "$CURL_ARGS"
if [[ $MOCK_CURL_EXIT != 0 ]]; then exit "$MOCK_CURL_EXIT"; fi
if [[ $MOCK_EMPTY == true ]]; then exit 0; fi
if [[ $MOCK_INVALID == true ]]; then printf '%s' '%%%'; exit 0; fi
base64 < "$CANONICAL_INIT"
`);
  writeFileSync(path.join(bin, 'bash'), `#!/bin/bash
set -euo pipefail
if [[ $1 == /usr/libexec/oci-growfs ]]; then
  [[ $# == 2 && $2 == -y ]]
  printf '%s\\n' 'growfs -y' >> "$TRACE"
  exit "$MOCK_GROW_EXIT"
fi
[[ $# == 1 && $1 == "$BOOTSTRAP_PATH" ]]
exec /bin/bash "$@"
`);
  chmodSync(path.join(bin, 'curl'), 0o755);
  chmodSync(path.join(bin, 'bash'), 0o755);
  const result = spawnSync('/bin/bash', [script], {
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, TRACE: trace, CURL_ARGS: path.join(dir, 'curl-args'), CANONICAL_INIT: canonical, BOOTSTRAP_PATH: bootstrap, MOCK_CURL_EXIT: '0', MOCK_GROW_EXIT: '0', MOCK_EMPTY: 'false', MOCK_INVALID: 'false', ...overrides },
    encoding: 'utf8'
  });
  const events = readFileSync(trace, 'utf8').trim().split('\n');
  const args = readFileSync(path.join(dir, 'curl-args'), 'utf8').trim().split('\n');
  return { result, events, args, cleanup: () => rmSync(dir, { recursive: true, force: true }) };
}

test('GPU bootstrap expands the filesystem before executing canonical OKE initialization', () => {
  const f = fixture();
  try {
    assert.equal(f.result.status, 0, f.result.stderr);
    assert.deepEqual(f.events, ['metadata', 'growfs -y', 'oke-init']);
    assert.ok(f.args.includes('Authorization: Bearer Oracle'));
    assert.equal(f.args.at(-1), 'http://169.254.169.254/opc/v2/instance/metadata/oke_init_script');
    assert.match(f.result.stdout, /root filesystem expansion[\s\S]*OKE node initialization[\s\S]*completed/);
  } finally { f.cleanup(); }
});

for (const [label, overrides, events, phase, code] of [
  ['metadata request failure', { MOCK_CURL_EXIT: '28' }, ['metadata'], 'IMDSv2 bootstrap download', 28],
  ['invalid encoded metadata', { MOCK_INVALID: 'true' }, ['metadata'], 'IMDSv2 bootstrap download', null],
  ['empty metadata', { MOCK_EMPTY: 'true' }, ['metadata'], 'IMDSv2 bootstrap download', 1],
  ['filesystem expansion failure', { MOCK_GROW_EXIT: '22' }, ['metadata', 'growfs -y'], 'root filesystem expansion', 22],
  ['canonical OKE initialization failure', { MOCK_INIT_EXIT: '31' }, ['metadata', 'growfs -y', 'oke-init'], 'OKE node initialization', 31]
]) {
  test(`GPU bootstrap fails closed on ${label}`, () => {
    const f = fixture(overrides);
    try {
      assert.notEqual(f.result.status, 0, JSON.stringify(f.result));
      if (code !== null) assert.equal(f.result.status, code);
      assert.deepEqual(f.events, events, JSON.stringify(f.result));
      assert.ok(f.result.stderr.includes(`Node bootstrap failed during ${phase}`), f.result.stderr);
      assert.doesNotMatch(f.result.stdout, /Node bootstrap completed/);
    } finally { f.cleanup(); }
  });
}
