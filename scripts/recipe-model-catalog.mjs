// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import { readFile, writeFile, mkdtemp, copyFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';
import { parse } from 'yaml';
const validId = id => typeof id === 'string' && /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(id);
const compare = (a,b) => a.toLowerCase()<b.toLowerCase()?-1:a.toLowerCase()>b.toLowerCase()?1:a<b?-1:a>b?1:0;
function date(value) {
  if(value==null) return null;
  if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value)||!Number.isFinite(Date.parse(value))||new Date(value).toISOString().slice(0,10)!==value) throw new Error(`Invalid recipe date: ${value}`);
  return value;
}
export function buildCatalog(recipes, policy, observedAt, sources=[]) {
  const maxAge=policy.max_recipe_age_days;
  if(maxAge!=null&&(!Number.isInteger(maxAge)||maxAge<0)) throw new Error('max_recipe_age_days must be null or a nonnegative integer');
  const cutoff=maxAge==null?null:new Date(Date.parse(observedAt)-maxAge*86400000).toISOString().slice(0,10);
  const models=new Map(); let excluded=0;
  for(const {recipe,source} of recipes) {
    if(!validId(recipe.model?.model_id)) throw new Error(`Invalid model ID in ${source.path}`);
    const added=date(recipe.meta?.date_added), updated=date(recipe.meta?.date_updated);
    if(cutoff&&added&&added<cutoff) {excluded++;continue;}
    const ids=new Set([recipe.model.model_id]);
    // Variants and their hardware overrides may name distinct HF checkpoints.
    function collect(value) {
      if(!value||typeof value!=='object') return;
      if(Object.hasOwn(value,'model_id')) {
        if(!validId(value.model_id)) throw new Error(`Invalid variant ID in ${source.path}`);
        ids.add(value.model_id);
      }
      for(const child of Object.values(value)) collect(child);
    }
    collect(recipe.variants);
    const tasks=recipe.meta?.tasks??[];
    if(!Array.isArray(tasks)||tasks.some(t=>typeof t!=='string')) throw new Error(`Invalid tasks in ${source.path}`);
    for(const id of ids) {
      const row=models.get(id)??{id,sha:null,model_revision_resolution:'discovery',release_date:null,tasks:[],recipes:[],support_evidence:'upstream_recipe_only'};
      row.tasks=[...new Set([...row.tasks,...tasks])].sort(compare);
      row.recipes.push({...source,recipe_model_id:recipe.model.model_id,date_added:added,date_updated:updated});
      models.set(id,row);
    }
  }
  const rows=[...models.values()].sort((a,b)=>compare(a.id,b.id));
  for(const row of rows) row.recipes.sort((a,b)=>compare(`${a.repository}/${a.path}`,`${b.repository}/${b.path}`));
  return {schema_version:'1.0',observed_at:observedAt,source:'vLLM structured recipes',sources,age_policy:{max_recipe_age_days:maxAge??null,date_basis:'recipe_date_added',cutoff,undated:'retained',excluded_recipes:excluded},recipe_count:recipes.length,models:rows};
}
async function fetchData(url, json=false) {
  const response=await fetch(url,{headers:{Accept:json?'application/vnd.github+json':'text/plain','User-Agent':'oke-llm-serving-catalog'},signal:AbortSignal.timeout(60000)});
  if(!response.ok) throw new Error(`Fetch failed (${response.status}): ${url}`);
  const chunks=[];let size=0;
  for await(const chunk of response.body) {size+=chunk.length;if(size>16*1024*1024)throw new Error(`Source exceeds 16 MiB: ${url}`);chunks.push(chunk);}
  const text=Buffer.concat(chunks).toString('utf8');return json?JSON.parse(text):text;
}
export async function refresh(root) {
  const policy=JSON.parse(await readFile(join(root,'catalogs/model-policy.json'),'utf8'));
  const sources=[], recipes=[];
  for(const source of policy.sources) {
    if(!/^vllm-project\/[A-Za-z0-9_.-]+$/.test(source.repository)||!source.prefix.endsWith('/'))throw new Error('Invalid recipe source policy');
    const commit=await fetchData(`https://api.github.com/repos/${source.repository}/commits/${encodeURIComponent(source.revision)}`,true);
    if(!/^[a-f0-9]{40}$/.test(commit.sha))throw new Error('Missing source commit SHA');
    const tree=await fetchData(`https://api.github.com/repos/${source.repository}/git/trees/${commit.sha}?recursive=1`,true);
    if(tree.truncated)throw new Error(`Truncated recipe enumeration: ${source.repository}`);
    const paths=tree.tree.filter(e=>e.type==='blob'&&e.path.startsWith(source.prefix)&&/\.ya?ml$/.test(e.path)).map(e=>e.path).sort(compare);
    if(!paths.length)throw new Error(`No recipes found: ${source.repository}/${source.prefix}`);
    sources.push({...source,sha:commit.sha,recipe_count:paths.length});
    // Bounded parallel reads; source failure aborts without replacing the current catalog.
    for(let i=0;i<paths.length;i+=8) {
      const batch=await Promise.all(paths.slice(i,i+8).map(async path=>{
        const url=`https://raw.githubusercontent.com/${source.repository}/${commit.sha}/${path}`;
        return {recipe:parse(await fetchData(url)),source:{repository:source.repository,sha:commit.sha,path,url,engine:source.engine}};
      }));recipes.push(...batch);
    }
    process.stderr.write(`${source.repository}: ${paths.length} recipes at ${commit.sha}\n`);
  }
  const catalog=buildCatalog(recipes,policy,new Date().toISOString(),sources);
  if(!catalog.models.length)throw new Error('No catalog models; existing files retained');
  const temporary=await mkdtemp(join(tmpdir(),'oke-recipe-catalog-'));
  try {
    const catalogPath=join(temporary,'models.json'), schemaPath=join(temporary,'schema.yaml');
    await writeFile(catalogPath,JSON.stringify(catalog,null,2)+'\n');
    await copyFile(join(root,'terraform/stacks/discovery/schema.yaml'),schemaPath);
    execFileSync('bash',[join(root,'scripts/generate-model-schema.sh'),catalogPath,schemaPath],{stdio:'inherit'});
    await copyFile(catalogPath,join(root,'catalogs/models.json'));
    await copyFile(schemaPath,join(root,'terraform/stacks/discovery/schema.yaml'));
  } finally {await rm(temporary,{recursive:true,force:true});}
  process.stderr.write(`Updated ${catalog.models.length} alphabetically ordered models across all recipe tasks.\n`);
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  refresh(resolve(process.argv[2]??'.')).catch(error=>{console.error(error.message);process.exitCode=1;});
}
