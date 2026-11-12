// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from 'node:test';
import assert from 'node:assert/strict';
import { buildCatalog } from '../../scripts/recipe-model-catalog.mjs';
const entry=(id,meta={},variants={})=>({recipe:{model:{model_id:id},meta,variants},source:{repository:'vllm-project/vllm',sha:'a'.repeat(40),path:`recipes/models/${id}.yaml`,engine:'vllm'}});
const observed='2026-11-11T00:00:00Z';
test('all tasks and checkpoint variants are retained, merged and alphabetized',()=>{
 const catalog=buildCatalog([
  entry('Zoo/speech',{tasks:['omni']},{fp8:{model_id:'Alpha/speech-fp8'}}),
  entry('beta/vision',{tasks:['multimodal']}),
  entry('Zoo/speech',{tasks:['audio']}),
  entry('Alpha/text',{tasks:['text']})
 ],{max_recipe_age_days:null},observed);
 assert.deepEqual(catalog.models.map(m=>m.id),['Alpha/speech-fp8','Alpha/text','beta/vision','Zoo/speech']);
 assert.deepEqual(catalog.models.at(-1).tasks,['audio','omni']);
 assert.equal(catalog.models.at(-1).recipes.length,2);
 assert.equal(catalog.models[0].sha,null);
 assert.equal(catalog.models[0].release_date,null);
});
test('age policy uses recipe addition date, preserves undated recipes and can be disabled',()=>{
 const entries=[entry('a/old',{date_added:'2020-01-01',date_updated:'2026-11-10'}),entry('a/new',{date_added:'2026-11-10'}),entry('a/undated')];
 const filtered=buildCatalog(entries,{max_recipe_age_days:365},observed);
 assert.deepEqual(filtered.models.map(m=>m.id),['a/new','a/undated']);
 assert.equal(filtered.age_policy.excluded_recipes,1);
 assert.equal(buildCatalog(entries,{max_recipe_age_days:null},observed).models.length,3);
 assert.throws(()=>buildCatalog(entries,{max_recipe_age_days:-1},observed));
 assert.throws(()=>buildCatalog([entry('a/b',{date_added:'2026-02-30'})],{},observed),/Invalid recipe date/);
});
test('malformed recipe IDs fail instead of silently dropping models',()=>{
 assert.throws(()=>buildCatalog([entry('bad')],{},observed),/Invalid model ID/);
 assert.throws(()=>buildCatalog([entry('a/b',{}, {bad:{model_id:'bad'}})],{},observed),/Invalid variant ID/);
});
