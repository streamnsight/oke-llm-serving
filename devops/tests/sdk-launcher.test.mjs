// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, rmSync, chmodSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
test('SDK launcher verifies the platform executable before running it',()=>{
 const dir=mkdtempSync(`${tmpdir()}/oke-sdk-launcher-`);
 try {
  const os=execFileSync('uname',['-s'],{encoding:'utf8'}).trim().toLowerCase();
  const arch=process.arch==='x64'?'amd64':process.arch;
  mkdirSync(`${dir}/scripts`);mkdirSync(`${dir}/bin/${os}_${arch}`,{recursive:true});
  const script=`${dir}/scripts/run-discovery-sdk.sh`, binary=`${dir}/bin/${os}_${arch}/oci-discovery`;
  copyFileSync(resolve(import.meta.dirname,'../../scripts/run-discovery-sdk.sh'),script);
  const executable='#!/bin/bash\nprintf \'{"result":"verified"}\\n\'\n';
  writeFileSync(binary,executable,{mode:0o755});writeFileSync(`${binary}.sha256`,'incorrect');
  assert.equal(spawnSync('bash',[script]).status,2);
  writeFileSync(`${binary}.sha256`,createHash('sha256').update(executable).digest('hex'));
  chmodSync(binary,0o644);
  assert.deepEqual(JSON.parse(execFileSync('bash',[script],{encoding:'utf8'})),{result:'verified'});
 } finally {rmSync(dir,{recursive:true,force:true});}
});
