// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

const source = readFileSync(new URL('../modules/llm-deployment/model-delivery/execution.tf', import.meta.url), 'utf8');
const expression = source.match(/MODEL_PIPELINE_IDS\s*=\s*(replace\(jsonencode\(sort\(local\.all_pipeline_ids\)\),[^\n]+\))/)?.[1];
assert.ok(expression, 'Use a single explicit Terraform escaping boundary for the native onboarding argument');
const prefix = 'ocid1.devopsdeploypipeline.oc1.ca-montreal-1.';
// The real failing IDs were 105 characters: losing their first JSON quotes
// caused jq's error at column 107. These are synthetic, same-format IDs.
const ids = ['d', 'b', 'a', 'c'].map(suffix => prefix + 'a'.repeat(104 - prefix.length) + suffix);
const logical = JSON.stringify(ids.toSorted());

function shellAssignment(value, doubleQuoted) {
  return spawnSync('bash', ['-c', `set -euo pipefail\nexport MODEL_PIPELINE_IDS=${doubleQuoted ? '"' : ''}${value}${doubleQuoted ? '"' : ''}\nprintf '%s' "$MODEL_PIPELINE_IDS" | jq -ce 'type=="array" and length==4 and all(.[];type=="string")' >/dev/null\nprintf '%s' "$MODEL_PIPELINE_IDS"`], { encoding: 'utf8' });
}

test('unescaped JSON reproduces the live Managed Shell jq column-107 failure', () => {
  for (const doubleQuoted of [false, true]) {
    const result = shellAssignment(logical, doubleQuoted);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Invalid numeric literal at line 1, column 107/);
    assert.notEqual(result.stdout, logical);
  }
});

test('the actual Terraform argument expression survives one shell assignment exactly', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'oke-onboarding-transport-'));
  try {
    const evaluated = spawnSync('terraform', [`-chdir=${dir}`, 'console', '-no-color'], {
      input: expression.replace('local.all_pipeline_ids', JSON.stringify(ids)) + '\n', encoding: 'utf8'
    });
    assert.equal(evaluated.status, 0, evaluated.stderr);
    const transport = JSON.parse(evaluated.stdout.trim());
    assert.ok(transport.includes('\\"'));
    for (const doubleQuoted of [false, true]) {
      const result = shellAssignment(transport, doubleQuoted);
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.stdout, logical);
      assert.deepEqual(JSON.parse(result.stdout), ids.toSorted());
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
