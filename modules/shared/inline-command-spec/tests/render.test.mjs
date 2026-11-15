// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

test('rendered plaintext heredocs preserve exact UTF-8 bytes and never expand embedded shell syntax', () => {
  const dir = mkdtempSync(join(tmpdir(), 'oke-inline-files-'));
  const files = {
    'run.sh': '#!/bin/bash\nprintf "%s\\n" "$SETTING"\n',
    'nested/no-final-newline.txt': "café 🌍 $HOME $(touch injected) `touch injected-too` 'double' \\",
    'empty.txt': '',
    'many-newlines.txt': 'line\n\n\n',
    'crlf.txt': 'first\r\nsecond\r\n',
  };
  try {
    writeFileSync(join(dir, 'main.tf'), `module "inline" {
  source = ${JSON.stringify(resolve('modules/shared/inline-command-spec'))}
  specification = {version="0.1",component="command",shell="bash",steps=[{type="Command",command="true"}]}
  files = jsondecode(file("${'${path.module}'}/files.json"))
}
output "command" { value = module.inline.preparation_command }
output "content" { value = module.inline.content }
output "byte_size" { value = module.inline.byte_size }
`);
    writeFileSync(join(dir, 'files.json'), JSON.stringify(files));
    for (const args of [['init', '-backend=false', '-input=false', '-no-color'], ['apply', '-auto-approve', '-input=false', '-no-color']]) {
      const result = spawnSync('terraform', args, { cwd: dir, encoding: 'utf8' });
      assert.equal(result.status, 0, result.stderr + result.stdout);
    }
    const result = spawnSync('terraform', ['output', '-json'], { cwd: dir, encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    const outputs = JSON.parse(result.stdout);
    assert.equal(outputs.byte_size.value, Buffer.byteLength(outputs.content.value));
    assert.doesNotMatch(outputs.command.value, /base64|\beval\b/);
    mkdirSync(join(dir, 'runtime'));
    const run = spawnSync('bash', ['-c', outputs.command.value], { cwd: join(dir, 'runtime'), encoding: 'utf8', env: { ...process.env, SETTING: 'must stay literal' } });
    assert.equal(run.status, 0, run.stderr + run.stdout);
    for (const [name, content] of Object.entries(files)) assert.deepEqual(readFileSync(join(dir, 'runtime', name)), Buffer.from(content), name);
    assert.equal(existsSync(join(dir, 'runtime/injected')), false);
    assert.equal(existsSync(join(dir, 'runtime/injected-too')), false);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
