// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync, readdirSync} from "node:fs";
import vm from "node:vm";
import {parse} from "yaml";
const moduleRoot = new URL("../modules/discovery/discovery-report/", import.meta.url);
const template = readFileSync(new URL("report.html.tftpl", moduleRoot), "utf8");
const script = readFileSync(new URL("report.js", moduleRoot), "utf8");
class Element {
  constructor(tag) { this.tag = tag; this.children = []; this.events = {}; this.value = ""; this._text = ""; this.open = false; this.hidden = false; this.attributes = {}; this.focused = false; }
  set textContent(value) { this._text = String(value); this.children = []; }
  get textContent() { return this._text + this.children.map(child => child.textContent).join(" "); }
  set innerHTML(_) { throw new Error("Untrusted report values must never become HTML"); }
  appendChild(child) { this.children.push(child); return child; }
  replaceChildren(...children) { this.children = children; }
  addEventListener(event, callback) { this.events[event] = callback; }
  setAttribute(name, value) { this.attributes[name] = String(value); }
  getAttribute(name) { return this.attributes[name]; }
  focus() { this.focused = true; }
}
function quota(scope = "REGION", current = 32, remaining = 16) {
  return {name: "gpu-count", scope, availability_domain: scope === "AD" ? "AD-1" : null, current_limit: current, remaining_headroom: remaining, unit: "GPUs"};
}
function option(region) {
  return {
    region, availability_domain: "AD-1", gpu_shape: "GPU.8", gpu_type: "Test GPU",
    capacity: {ad_available_hosts: 17, ad_available_gpus: 136, regional_available_gpus: 160, regional_known_reported_gpus: 160, regional_coverage: "complete", entitled_hosts: 2, observed_at: "scan-time", limits: [quota()]},
    allocation: {required_gpus_per_replica: 4, tensor_parallel_size: 4, pipeline_parallel_size: 1, gpus_per_host: 8, required_hosts: 1, allocated_gpus: 8, replicas: 2, replicas_per_host: 2, unused_gpus: 0},
    memory_gb: {per_gpu: 40, estimated_per_gpu: 30}, memory_method: "analytical_requires_validation", configuration_status: "suggested_requires_validation", runtime_validation: "not_run", components: ["prometheus"], integration_requirements: [],
    serving: {framework: "vllm", image: "vllm/vllm-openai@sha256:fixture", source_hardware: "h100", selected_hardware: "a100", args: ["--tool-call-parser", "qwen3_coder", "--tensor-parallel-size", "1"], environment: {SETTING: "value with spaces"}, original_argv: ["vllm", "serve", "org/model", "--tensor-parallel-size", "1"], source_url: "https://recipes.vllm.ai/org/model"},
    links: {launch_url: "https://cloud.oracle.com/resourcemanager/stacks/create?region=" + region + "&zipUrl=infra", download_url: "https://objectstorage.example/" + region + "-infra.zip", expires_at: "expiry-time", model_deployment: {launch_url: "https://cloud.oracle.com/resourcemanager/stacks/create?region=" + region + "&zipUrl=model", download_url: "https://objectstorage.example/" + region + "-model.zip", expires_at: "expiry-time"}},
  };
}
function execute(overrides = {}) {
  const report = {
    model: {repository: "org/model", revision: "pinned", model_type: "llama", architecture: "dense", dimensions: {layers: 32, heads: 32, kv_heads: 8}, parameter_count: 2000000000, checkpoint_formats: ["safetensors"], huggingface_url: "https://huggingface.co/org/model/tree/pinned", context_length: 4096, concurrency_per_replica: 4, memory_gb: {checkpoint_download: 4, resident_weights: 4, kv_per_replica: null, total_estimated: null}, memory_status: "unsupported", memory_reasons: ["No estimator"]},
    scan: {assessed_regions: ["eu-frankfurt-1", "us-chicago-1"]}, publication: {published_at: "published-time", expires_at: "expiry-time"},
    option_count: 2, recommended_option_id: "first", failure_summary: [], notices: ["Counts are a snapshot"],
    options: {first: option("eu-frankfurt-1"), second: option("us-chicago-1")},
    regional_capacity: [{region: "eu-frankfurt-1", gpu_shape: "GPU.8", gpus_per_host: 8, available_gpus: 136, available_hosts: 17, coverage: "complete", expected_ads: 1, known_ads: 1, limit_increase_possible: true, minimum_model_hosts: null, limits: [quota("AD", 0, 0)], availability_domains: [{availability_domain: "AD-1", available_hosts: 17, entitled_hosts: 0, limits: [quota("AD", 0, 0)], entitlement_status: "limit_increase_required", limit_increase_requests: [{limit_name: "gpu-count", current_limit: 0, scope: "AD", minimum_gpus_for_whole_hosts: null}]}]}], ...overrides,
  };
  const nodes = Object.fromEntries([...template.matchAll(/\bid="([^"]+)"/g)].map(match => [match[1], new Element("div")]));
  nodes["report-data"].textContent = JSON.stringify(report); nodes.sort.value = "allocated";
  const created = [], document = {getElementById: id => nodes[id], createElement: tag => {const node = new Element(tag); created.push(node); return node;}};
  const context = {document, URL}; vm.runInNewContext(script, context, {timeout: 1000});
  return {nodes, created, context};
}
test('unavailable cache features explain compatibility without hiding hardware or launch links',()=>{
 const row=option('region-one');row.cache_capabilities={routing:{kvaware:{selectable:false,status:'unavailable',reasons:['Hybrid cache requires MP; the current router cannot consume MP events.']}},lmcache:{mp:{selectable:true,status:'requires_image_validation',reasons:[]},inprocess:{selectable:false,status:'unsupported',reasons:['Hybrid cache layout is unsupported.']}}};
 const {nodes,created}=execute({options:{first:row},option_count:1});
 assert.match(nodes.options.textContent,/KV-aware routing: unavailable/);
 assert.match(nodes.options.textContent,/current router cannot consume MP events/);
 assert.match(nodes.options.textContent,/In-process LMCache: unsupported/);
 assert.equal(created.filter(n=>n.className==='option').length,1);
 assert(created.some(n=>n.tag==='a'&&n.href.includes('zipUrl=model')));
});
test('RMS controls do not advertise unavailable KV-aware routing',()=>{
 for(const path of ['../schema.yaml','../templates/llm-deployment/schema.yaml']){
  const schema=parse(readFileSync(new URL(path,import.meta.url),'utf8'));
  assert(!schema.variables.routing_mode.enum.includes('kvaware'));
 }
});
test("GPU sizing is visible with collapsed allocation and location-specific launch actions", () => {
  const {nodes, created} = execute();
  assert.equal(nodes.options.children.length, 1);
  assert.equal(nodes.options.children[0].tag, "article");
  assert.match(nodes.options.children[0].children[0].textContent, /GPUs used \/ replica/);
  assert.match(nodes.options.textContent, /2 replicas · 8 GPUs allocated/);
  assert.match(nodes.options.textContent, /expiry-time/);
  assert.equal(created.filter(n => n.className === "location").length, 2);
  assert.ok(created.filter(n => n.className === "location" || n.className === "recipe-details allocation-details").every(n => n.tag === "details" && !n.open));
  const hrefs = created.filter(n => n.tag === "a").map(n => n.href);
  for (const region of ["eu-frankfurt-1", "us-chicago-1"]) {
    assert.ok(hrefs.some(href => href.includes(region + "-model.zip")));
    assert.ok(hrefs.some(href => href.includes(region + "-infra.zip")));
    assert.ok(hrefs.some(href => href.includes("region=" + region + "&zipUrl=model")));
  }
  nodes.search.value = "frankfurt"; nodes.search.events.input();
  assert.equal(nodes.options.children.length, 1);
  assert.match(nodes.options.textContent, /eu-frankfurt-1/);
  assert.doesNotMatch(nodes.options.textContent, /us-chicago-1/);
});

test("model metadata, unknown memory and limit review remain visible without options", () => {
  const {nodes} = execute({options: {}, option_count: 0, failure_summary: ["No confirmed serving layout"]});
  assert.match(nodes["model-details"].textContent, /Transformer layers 32/);
  assert.match(nodes["model-details"].textContent, /safetensors/);
  assert.match(nodes["memory-metrics"].textContent, /KV cache \/ replica Unknown/);
  assert.match(nodes["memory-status"].textContent, /Complete memory estimate unavailable/);
  assert.match(nodes.failures.textContent, /No confirmed serving layout/);
  assert.match(nodes.capacity.textContent, /Review limit increase/);
  assert.match(nodes.capacity.textContent, /Model sizing unknown/);
  assert.match(nodes.capacity.textContent, /gpu-count/);
});
test("planned command overrides managed topology while preserving original recipe evidence", () => {
  const {created} = execute();
  const blocks = created.filter(node => node.tag === "pre").map(node => node.textContent.replace(/ \\\n\s*/g, " "));
  const planned = blocks.find(command => command.includes("--max-model-len"));
  assert.match(planned, /--tensor-parallel-size 4/);
  assert.doesNotMatch(planned, /--tensor-parallel-size 1/);
  assert.match(planned, /--max-model-len 4096/);
  assert.match(planned, /--max-num-seqs 4/);
  assert.match(planned, /--revision pinned/);
  assert.match(planned, /--tool-call-parser qwen3_coder/);
  assert.ok(blocks.some(command => command.includes("--tensor-parallel-size 1")), "retain original upstream command separately");
});
test("deployment actions precede technical serving configuration", () => {
  const {created} = execute();
  for (const option of created.filter(node => node.className === "option")) {
    assert.ok(option.textContent.indexOf("Model project and pipelines") < option.textContent.indexOf("Serving configuration"));
  }
});
test("zero and unknown-only supply are hidden while positive supply with zero limits remains", () => {
  const positive = {region: "needs-limits", gpu_shape: "GPU", available_hosts: 3, available_gpus: 24, availability_domains: [{availability_domain: "AD",available_hosts: 3,entitled_hosts: 0,limits:[quota("AD",0,0)],limit_increase_requests:[{limit_name:"gpu-count",current_limit:0,scope:"AD"}]}], limit_increase_possible: true};
  const {nodes} = execute({regional_capacity: [positive, {...positive,region:"zero",available_hosts:0,available_gpus:0,availability_domains:[{availability_domain:"AD",available_hosts:0}]}, {...positive,region:"unknown",available_hosts:null,available_gpus:null,availability_domains:[{availability_domain:"AD",available_hosts:null}]}]});
  assert.equal(nodes.capacity.children.length, 1);
  assert.match(nodes.capacity.textContent, /needs-limits/);
  assert.match(nodes.capacity.textContent, /Review limit increase/);
});
test("partial hybrid memory and planning budget have distinct labels", () => {
  const {nodes} = execute({model: {repository:"Qwen/model", context_length:4096,concurrency_per_replica:4,memory_status:"unsupported",memory_gb:{resident_weights:55.56,full_attention_kv:1.07,total_estimated:null},recipe_memory_budget_gb:71.83,partial_memory:{full_attention_layers:16,linear_attention_layers:48},planning_memory:{weight_bytes:55560000000,kv_surrogate_bytes:4290000000,safety_margin_fraction:0.2,recipe_minimum_bytes:67000000000,selected_payload_budget_bytes:71830000000,runtime_allowance_per_gpu_bytes:2147483648}}});
  assert.match(nodes["memory-metrics"].textContent, /Weights \/ replica 55.56 GB/);
  assert.match(nodes["memory-metrics"].textContent, /Full-attention KV \/ replica 1.07 GB/);
  assert.match(nodes["memory-metrics"].textContent, /Sizing budget \/ replica 71.83 GB/);
  assert.match(nodes["memory-status"].textContent, /not an estimate of actual hybrid-cache allocation/);
});
test("untrusted metadata is text and unsafe deployment/source URLs are rejected", () => {
  const malicious = "</script><script>globalThis.injected=true</script>", unsafe = option(malicious);
  unsafe.links = {launch_url: "javascript:globalThis.injected=true", download_url: "data:text/html,unsafe", model_deployment: {launch_url: "javascript:bad", download_url: "file:///tmp/bad"}};
  unsafe.serving.source_url = "data:text/html,bad";
  const {nodes, created, context} = execute({options: {unsafe}, option_count: 1});
  assert.match(nodes.options.textContent, /<\/script><script>/); assert.equal(context.injected, undefined);
  assert.ok(created.filter(node => node.tag === "a").every(node => node.href.startsWith("https:")));
  assert.equal(created.filter(node => node.tag === "script").length, 0);
  assert.doesNotMatch(script, /\binnerHTML\b/);
});
test("RMS exposes exactly one typed report-link output", () => {
  const root = new URL("../", import.meta.url);
  const outputs = readdirSync(root).filter(file => file.endsWith(".tf")).flatMap(file => [...readFileSync(new URL(file, root), "utf8").matchAll(/^output\s+"([^"]+)"/gm)].map(match => match[1]));
  assert.deepEqual(outputs, ["comparison_report_url"]);
  const schema = parse(readFileSync(new URL("schema.yaml", root), "utf8"));
  assert.deepEqual(Object.keys(schema.outputs).filter(key => schema.outputs[key].type === "link"), ["comparison_report_url"]);
  assert.equal(schema.outputs.comparison_report_url.type, "link");
  assert.equal(schema.primaryOutputButton, "${comparison_report_url}");
});
test("discovery excludes deployment-policy inputs and downstream forms own them", () => {
  const root = new URL("../", import.meta.url);
  const discovery = parse(readFileSync(new URL("schema.yaml", root), "utf8"));
  const variables = readFileSync(new URL("variables.tf", root), "utf8");
  for (const name of ["monitoring_enabled", "autoscaling_enabled", "model_storage_mode", "query_resource_availability", "only_shapes_with_limits", "include_diagnostics", "skip_gpu_allocation"]) {
    assert.equal(discovery.variables[name], undefined);
    assert.ok(!discovery.variableGroups.some(group => group.variables.includes(name)));
    assert.ok(!variables.includes(`variable "${name}"`));
  }
  const infra = parse(readFileSync(new URL("templates/infrastructure/schema.yaml", root), "utf8"));
  const model = parse(readFileSync(new URL("templates/llm-deployment/schema.yaml", root), "utf8"));
  assert.equal(infra.variables.skip_gpu_allocation.default, false);
  assert.equal(infra.variables.monitoring_enabled.default, true);
  assert.equal(infra.variables.keda_enabled.default, true);
  assert.equal(infra.variables.autoscaling_enabled, undefined);
  assert.equal(model.variables.monitoring_enabled.default, true);
  assert.equal(model.variables.autoscaling_enabled.default, false);
  assert.ok(model.variables.storage_mode.enum.includes("staged_object_storage"));
});

test("identical GPU topology groups locations while preserving each AD's capacity and limits", () => {
  const first = option("region-a"), second = option("region-a"), third = option("region-b");
  first.capacity = {...first.capacity, ad_available_hosts: 34, ad_available_gpus: 34, regional_available_gpus: 999, limits: [quota("REGION", 4, 2)]};
  second.availability_domain = "AD-2"; second.capacity = {...second.capacity, ad_available_hosts: 5, ad_available_gpus: 40};
  const {nodes, created} = execute({options: {first, second, third}, option_count: 3});
  assert.equal(nodes.options.children.length, 1);
  const locations = created.filter(node => node.className === "location");
  assert.equal(locations.length, 3);
  assert.match(locations[0].children[0].textContent, /34 GPUs available in AD/);
  assert.match(locations[0].children[0].textContent.replace(/\s+/g," "), /Region: 4 \(below required allocation of 8 GPUs\)/);
  assert.match(locations[0].children[0].textContent.replace(/\s+/g," "), /Headroom Region: 2 \(below required allocation of 8 GPUs\)/);
  assert.doesNotMatch(locations[0].children[0].textContent, /999/);
  assert.match(locations[1].children[0].textContent, /AD-2/);
  nodes.search.value = "AD-2"; nodes.search.events.input();
  assert.equal(nodes.options.children.length, 1);
  assert.match(nodes.options.textContent, /AD-2/); assert.doesNotMatch(nodes.options.textContent, /AD-1/);
});

test("capacity table shows per-AD supply and shared regional limit without a regional supply sum", () => {
  const {nodes} = execute({regional_capacity: [{
    region: "region-a", gpu_shape: "GPU.1", gpus_per_host: 1, available_hosts: 54, available_gpus: 54,
    known_ads: 2, expected_ads: 2, limits: [quota("REGION", 4, 2)],
    availability_domains: [{availability_domain: "AD-1", available_hosts: 34, limits:[quota("REGION",4,2)]}, {availability_domain: "AD-2", available_hosts: 20, limits:[quota("REGION",4,2)]}]
  }]});
  assert.equal(nodes.capacity.children.length,2);
  assert.match(nodes.capacity.children[0].children[0].textContent,/region-a AD-1/);
  assert.match(nodes.capacity.children[1].children[0].textContent,/region-a AD-2/);
  assert.match(nodes.capacity.children[0].children[4].textContent.replace(/\s+/g," "),/34 GPUs \/ 34 hosts physically available/);
  assert.match(nodes.capacity.children[1].children[4].textContent.replace(/\s+/g," "),/20 GPUs \/ 20 hosts physically available/);
  assert.match(nodes.capacity.textContent.replace(/\s+/g," "), /limit 4 \/ left 2 Region · GPUs/);
  assert.doesNotMatch(nodes.capacity.textContent, /54 GPUs|hosts in region/);
});
test("unknown location limits and units are explicit; zero headroom is not unknown", () => {
  const row = option("region-a");
  row.capacity.limits = [{...quota("GLOBAL", null, 0), unit: "units (unverified)"}];
  const {created} = execute({options: {row}, option_count: 1});
  const summary = created.find(n => n.className === "location").children[0].textContent.replace(/\s+/g," ");
  assert.match(summary, /Global: Unknown units \(unverified\)/);
  assert.match(summary, /Headroom Global: 0 units \(unverified\)/);
});

test("capacity rows put region and AD first and bold only numeric quantities beside normal units", () => {
  const ad="jVha:AP-MELBOURNE-1-AD-1";
  const {nodes}=execute({regional_capacity:[{region:"ap-melbourne-1",gpu_shape:"BM.GPU.A10.4",memory_gb_per_gpu:24,gpus_per_host:4,known_ads:1,expected_ads:1,minimum_model_hosts:1,availability_domains:[{availability_domain:ad,available_hosts:7,entitled_hosts:3,limits:[quota("REGION",32,12)],limit_increase_requests:[]}]}]});
  const row=nodes.capacity.children[0],[identity,needed,perHost,limits,physical]=row.children;
  assert.equal(identity.children[0].tag,"strong");assert.equal(identity.children[0].textContent,"ap-melbourne-1 "+ad);
  assert.equal(identity.children[1].textContent,"BM.GPU.A10.4");assert.equal(identity.children[1].tag,"div");
  assert.equal(identity.children[2].textContent,"24 GB per GPU");
  const bold=node=>[...(node.tag==="strong"?[node.textContent]:[]),...node.children.flatMap(bold)];
  assert.deepEqual(bold(perHost),["4"]);assert.deepEqual(bold(physical),["28"]);assert.deepEqual(bold(limits),["32","12"]);
  assert.match(physical.textContent.replace(/\s+/g," "),/^28 GPUs \/ 7 hosts physically available/);
  assert.equal(physical.children[0].children[1].tag,"span");
});
test("each AD row keeps its own limits and exclusion badge and is searchable by AD", () => {
  const {nodes}=execute({regional_capacity:[{region:"region-a",gpu_shape:"GPU.4",gpus_per_host:4,known_ads:2,expected_ads:2,limits:[quota("REGION",999,999)],availability_domains:[
    {availability_domain:"AD-1",available_hosts:7,limits:[quota("AD",0,0)],limit_increase_requests:[{limit_name:"gpu-count",scope:"AD",current_limit:0}]},
    {availability_domain:"AD-2",available_hosts:3,limits:[{...quota("AD",32,8),availability_domain:"AD-2"}],limit_increase_requests:[]}
  ]}]});
  const [first,second]=nodes.capacity.children;
  assert.match(first.textContent,/Review limit increase/);assert.doesNotMatch(second.textContent,/Review limit increase/);
  assert.doesNotMatch(first.textContent,/999/);assert.doesNotMatch(second.textContent,/999/);
  assert.match(second.children[3].textContent.replace(/\s+/g," "),/limit 32 \/ left 8 AD AD-2 · GPUs/);
  nodes["capacity-search"].value="AD-2";nodes["capacity-search"].events.input();
  assert.equal(nodes.capacity.children.length,1);assert.match(nodes.capacity.children[0].children[0].textContent,/AD-2/);
});

test("incompatible regional supply remains visible with an explicit dtype reason", () => {
  const {nodes} = execute({options:{},option_count:0,regional_capacity:[{region:"region",gpu_shape:"A10",gpus_per_host:1,known_ads:1,expected_ads:1,known_reported_hosts:3,dtype_compatibility:{status:"not_compatible",required_precision:"fp8",reason:"Native FP8 kernels unavailable"},availability_domains:[{availability_domain:"AD",available_hosts:3,limits:[]}]}]});
  assert.match(nodes.capacity.textContent,/Not compatible/);
  assert.match(nodes.capacity.textContent,/fp8: Native FP8 kernels unavailable/);
  assert.match(nodes.capacity.textContent,/3 hosts physically available/);
  assert.equal(nodes.options.children.length,0);
});
test("generic planning scenario is numeric and explicitly heuristic without deployment options", () => {
  const {nodes} = execute({options:{},option_count:0,model:{repository:"future/model",memory_status:"heuristic",memory_gb:{resident_weights:2495.77},component_planning:{payload_budget_bytes:3768e9,weight_source:"hub_dtype_counts",status:"heuristic_uncalibrated",cache_source:"all_layer_dense_surrogate_not_upper_bound",cache_scenario_bytes:395e9,workspace_allowance_bytes:249e9,safety_margin_fraction:0.2,formula:"payload formula",interpretation:"Planning scenario, not a guaranteed upper bound"}}});
  assert.match(nodes["memory-metrics"].textContent,/3,768 GB|3768 GB/);
  assert.match(nodes["memory-metrics"].children[2].textContent,/KV planning \/ replica 395 GB All-layer scenario · unvalidated/);
  assert.match(nodes["memory-status"].textContent,/Heuristic planning scenario available/);
  assert.match(nodes["memory-status"].textContent,/not a guaranteed upper bound/);
});

test("unprofiled cache planning is visible while complete and partial KV estimates take precedence", () => {
  const model={repository:"future/multimodal",context_length:262144,concurrency_per_replica:1,memory_status:"heuristic",memory_gb:{kv_per_replica:null,full_attention_kv:null},component_planning:{cache_scenario_bytes:51539607552,cache_source:"all_layer_dense_surrogate_not_upper_bound"}};
  const cache=override=>execute({options:{},option_count:0,model:{...model,...override}}).nodes["memory-metrics"].children[2].textContent;
  assert.equal(cache({}),"KV planning / replica 51.54 GB All-layer scenario · unvalidated");
  assert.equal(cache({memory_gb:{kv_per_replica:7,full_attention_kv:3}}),"KV cache / replica 7 GB");
  assert.equal(cache({memory_gb:{kv_per_replica:null,full_attention_kv:3}}),"Full-attention KV / replica 3 GB");
  assert.equal(cache({component_planning:{cache_scenario_bytes:25e9,cache_source:"weight_fraction_uncalibrated"}}),"Cache allowance / replica 25 GB Weight-based scenario · unvalidated");
  assert.equal(cache({component_planning:{cache_scenario_bytes:25e9,cache_source:"future_scenario"}}),"Cache allowance / replica 25 GB Planning scenario · unvalidated");
  assert.equal(cache({component_planning:{cache_scenario_bytes:null}}),"KV cache / replica Unknown");
});

test("regional quota uses limit / left labels and preserves AD scope, zero and unknown", () => {
 const {nodes}=execute({regional_capacity:[{region:"us-phoenix-1",gpu_shape:"VM.GPU.A10.1",gpus_per_host:1,availability_domains:[{availability_domain:"jVha:PHX-AD-3",available_hosts:8,limits:[{...quota("AD",32,32),availability_domain:"jVha:PHX-AD-3"},{...quota("REGION",null,0)}]}]}]});
 const text=nodes.capacity.textContent.replace(/\s+/g," ");
 assert.match(text,/limit 32 \/ left 32/);assert.match(text,/AD jVha:PHX-AD-3 · GPUs/);assert.match(text,/limit Unknown \/ left 0/);
});

test("location quota avoids repeating its selected AD but keeps detailed scope", () => {
  const row=option("ca-montreal-1");row.availability_domain="jVha:CA-MONTREAL-1-AD-1";
  row.capacity.limits=[{...quota("AD",56,52),availability_domain:row.availability_domain}];
  const {created}=execute({options:{row},option_count:1});
  const location=created.find(n=>n.className==="location"), summary=location.children[0];
  assert.match(summary.children[2].textContent,/56\s+GPUs/);
  assert.match(summary.children[3].textContent,/52\s+GPUs/);
  assert.doesNotMatch(summary.children[2].textContent,/jVha|AD /);
  assert.match(summary.children[0].textContent,/jVha:CA-MONTREAL-1-AD-1/);
  assert.match(location.children[1].textContent,/AD jVha:CA-MONTREAL-1-AD-1/);
});

test("GPU summary shows usage, topology, replica memory and allocated GPU total before locations", () => {
  const {nodes} = execute();
  const card=nodes.options.children[0], stats=card.children[0].children.slice(1);
  assert.match(stats[0].textContent, /^4 GPUs used \/ replica/);
  assert.match(stats[1].textContent, /^4 × 1 TP × PP/);
  assert.match(stats[2].textContent, /^120 GB Total memory \/ replica \(estimate\)/);
  assert.match(stats[3].textContent, /^8 GPUs allocated · total/);
  assert.match(stats[3].textContent, /2 replicas · 1 host/);
  assert.doesNotMatch(card.children[0].textContent,/eu-frankfurt|Limit|Headroom/);
  assert.ok(card.textContent.indexOf("Allocation and replica packing") < card.textContent.indexOf("Available locations"));
});

test("regional columns compare each GPU quantity with the full host allocation", () => {
  const {nodes, created} = execute({regional_capacity: [{
    region: "region", gpu_shape: "GPU.8", gpus_per_host: 8, minimum_model_gpus: 9, minimum_model_hosts: 2,
    availability_domains: [{availability_domain: "AD", available_hosts: 1, limits: [quota("REGION", 8, 4)]}]
  }]});
  const [identity, needed, perHost, limits, physical] = nodes.capacity.children[0].children;
  assert.match(identity.textContent, /region AD/);
  assert.match(needed.textContent, /^9 Memory lower bound \/ replica Allocate 16 GPUs \/ 2 hosts/);
  assert.equal(perHost.textContent, "8");
  assert.match(limits.textContent.replace(/\s+/g," "), /limit 8/);
  assert.match(physical.textContent, /^8/);
  const short = created.filter(node => node.className === "insufficient");
  assert.deepEqual(short.map(node => node.textContent), ["8", "8", "4"]);
  assert.ok(short.every(node => node.title.includes("16 GPUs")));
  assert.match(template, /GPUs per model instance<\/th>.*GPUs per host<\/th>.*Current limit and headroom<\/th>.*Physical capacity per AD<\/th>/);
});

test("quota and capacity equality suffice; unknown sizing or quota units stay neutral", () => {
  for (const [needed, hosts, limit, left, unit, available, expected] of [
    [4, 1, 8, 8, "GPUs", 1, 0],
    [4, 1, 8, 0, "GPUs", 1, 1],
    [4, 1, 4, 8, "GPUs", 1, 1],
    [4, 1, null, -1, "GPUs", 1, 0],
    [4, 1, 0, 0, "units (unverified)", 1, 0],
    [null, null, 0, 0, "GPUs", 1, 0],
    [9, 2, 16, 16, "GPUs", 1, 1],
  ]) {
    const {created} = execute({options: {}, option_count: 0, regional_capacity: [{
      region: "region", gpu_shape: "GPU.8", gpus_per_host: 8, minimum_model_gpus: needed, minimum_model_hosts: hosts,
      availability_domains: [{availability_domain: "AD", available_hosts: available, limits: [{...quota("AD", limit, left), unit}]}]
    }]});
    assert.equal(created.filter(node => node.className === "insufficient").length, expected, JSON.stringify({needed, hosts, limit, left, unit, available}));
  }
});

test("option quota and physical shortages are marked individually against allocated GPUs", () => {
  const row = option("region");
  row.capacity = {...row.capacity, ad_available_gpus: 4, limits: [quota("REGION", 4, 8), {...quota("GLOBAL", 0, 0), unit: "units (unverified)"}]};
  const {created} = execute({options: {row}, option_count: 1});
  assert.deepEqual(created.filter(node => node.className === "insufficient").map(node => node.textContent), ["4", "4"]);
});

function servingLayouts() {
  const combined = option("ca-montreal-1"), pd = option("ca-montreal-1");
  combined.availability_domain = pd.availability_domain = "jVha:CA-MONTREAL-1-AD-1";
  combined.allocation = {...combined.allocation, required_gpus_per_replica: 2, tensor_parallel_size: 2, gpus_per_host: 4, allocated_gpus: 4};
  pd.allocation = {...combined.allocation, replicas: 1};
  pd.serving_mode = "disaggregated"; pd.prefill_replicas = 1; pd.decode_replicas = 1;
  pd.launch_variables = {infrastructure: {node_count: 1}, model: {serving_mode: "disaggregated", prefill_replicas: 1, replicas: 1}};
  pd.links = {...combined.links, launch_url: combined.links.launch_url + "&zipUrlVariables=" + encodeURIComponent(JSON.stringify(pd.launch_variables.infrastructure)), model_deployment: {...combined.links.model_deployment, launch_url: combined.links.model_deployment.launch_url + "&zipUrlVariables=" + encodeURIComponent(JSON.stringify(pd.launch_variables.model))}};
  return {
    aggregated: {title: "Combined prefill + decode", status: "available", recommended_option_id: "base", options: {base: combined}},
    disaggregated: {title: "Separate prefill / decode (P/D)", status: "eligible_for_testing", recommended_option_id: "base", options: {base: pd}}
  };
}
test("serving tabs show actual role allocation and shared archives with distinct launch presets", () => {
  const layouts = servingLayouts(), {nodes, created} = execute({serving_layouts: layouts});
  assert.match(nodes.options.textContent, /2 replicas · 4 GPUs allocated/);
  nodes["layout-tab-disaggregated"].events.click();
  assert.equal(nodes["layout-tab-disaggregated"].getAttribute("aria-selected"), "true");
  assert.equal(nodes["layout-tab-aggregated"].getAttribute("aria-selected"), "false");
  assert.equal(nodes["layout-tab-disaggregated"].tabIndex, 0);
  assert.equal(nodes["layout-tab-aggregated"].tabIndex, -1);
  assert.equal(nodes["layout-panel"].getAttribute("aria-labelledby"), "layout-tab-disaggregated");
  assert.match(nodes["option-count"].textContent, /1 GPU option · 1 location/);
  assert.match(nodes.options.textContent, /2 GPUs used \/ role instance/);
  assert.match(nodes.options.textContent, /1 prefill \+ 1 decode · 4 GPUs allocated/);
  assert.match(nodes.options.textContent, /Role pods request 4 GPUs/);
  assert.match(nodes.options.textContent, /Prefill \/ decode instances 1 \/ 1/);
  assert.match(nodes.options.textContent, /Settings for a manual ZIP upload/);
  assert.match(nodes.options.textContent, /packaged defaults describe combined serving/);
  assert.match(nodes.options.textContent, /role-specific native NIXL transfer/);
  assert.doesNotMatch(nodes.options.textContent, /Planned engine command|Replicas \/ replicas per host|Growth at scan time/);
  const cards=nodes.options.children;
  assert.equal(cards.length,1);
  const pdLinks=created.filter(n=>n.tag==="a"&&n.href.includes("zipUrlVariables")).map(n=>new URL(n.href));
  assert.equal(pdLinks.length,2);
  assert.equal(pdLinks[0].searchParams.get("zipUrl"),new URL(layouts.aggregated.options.base.links.launch_url).searchParams.get("zipUrl"));
  assert.deepEqual(JSON.parse(pdLinks[1].searchParams.get("zipUrlVariables")),layouts.disaggregated.options.base.launch_variables.model);
});
test("serving tabs retain filters, sorting, region groups and tab-specific recommendations", () => {
  const layouts=servingLayouts();
  layouts.disaggregated.recommended_option_id="other";
  layouts.disaggregated.options.other={...layouts.disaggregated.options.base,region:"eu-frankfurt-1",availability_domain:"AD-2",allocation:{...layouts.disaggregated.options.base.allocation,required_hosts:2,allocated_gpus:8}};
  const {nodes}=execute({serving_layouts:layouts});
  nodes["layout-tab-disaggregated"].events.click();
  assert.equal(nodes.options.children.length,2);
  assert.match(nodes.options.children[1].textContent,/Recommended starting point/);
  assert.doesNotMatch(nodes.options.children[0].textContent,/Recommended starting point/);
  nodes.sort.value="allocated";nodes.sort.events.change();
  assert.match(nodes.options.children[0].textContent,/ca-montreal-1/);
  nodes.search.value="AD-2";nodes.search.events.input();
  assert.equal(nodes.options.children.length,1);assert.match(nodes.options.textContent,/eu-frankfurt-1/);
  nodes["layout-tab-aggregated"].events.click();
  assert.equal(nodes.options.children.length,0);assert.equal(nodes["option-empty"].hidden,false);
  assert.equal(nodes["option-empty"].textContent,"No matching deployment options.");
});
test("tab keyboard navigation moves focus and keeps the selected panel labelled", () => {
  const {nodes}=execute({serving_layouts:servingLayouts()});let prevented=0;
  const key=(id,key)=>nodes["layout-tab-"+id].events.keydown({key,preventDefault(){prevented++;}});
  key("aggregated","ArrowRight");assert.equal(nodes["layout-tab-disaggregated"].focused,true);
  assert.equal(nodes["layout-panel"].getAttribute("aria-labelledby"),"layout-tab-disaggregated");
  key("disaggregated","Home");assert.equal(nodes["layout-tab-aggregated"].focused,true);
  key("aggregated","ArrowLeft");assert.equal(nodes["layout-panel"].getAttribute("aria-labelledby"),"layout-tab-disaggregated");
  key("disaggregated","End");assert.equal(prevented,4);
  key("disaggregated","Tab");assert.equal(prevented,4);
});
test("unsupported or capacity-unconfirmed P/D remains visible with reasons and no launch actions", () => {
  for (const reason of ["Mixed sliding/full attention is outside this adapter.","Only one host is confirmed; P/D needs two hosts.","Quantity-specific entitlement is unknown."]) {
    const layouts=servingLayouts();layouts.disaggregated={...layouts.disaggregated,options:{},reasons:[reason],status:"not_available"};
    const {nodes}=execute({serving_layouts:layouts});nodes["layout-tab-disaggregated"].events.click();
    assert.match(nodes["layout-status"].textContent,/No confirmed P\/D option/);
    assert(nodes["layout-status"].textContent.includes(reason));
    assert.equal(nodes.options.children.length,0);
    assert.match(nodes["option-count"].textContent,/0 GPU options · 0 locations/);
  }
});
test("legacy reports expose an unassessed P/D tab without inventing eligibility", () => {
  const {nodes}=execute();nodes["layout-tab-disaggregated"].events.click();
  assert.match(nodes["layout-status"].textContent,/not assessed in this report/);
  assert.equal(nodes.options.children.length,0);
  nodes["layout-tab-aggregated"].events.click();assert.equal(nodes.options.children.length,1);
  assert.match(template,/MoE models can support P\/D/);
  assert.match(template,/twice the GPUs of one combined instance/);
  assert.match(template,/does not always double an existing replicated fleet/);
  assert.match(template,/KV-aware routing/);
});

test("key model facts humanize parameters and distinguish declared maximum context from workload", () => {
  for (const [count, expected] of [[27000000000, "27B"], [2400000000000, "2.4T"], [600000000, "600M"], [null, "Unknown"]]) {
    const {nodes}=execute({model:{repository:"org/model",parameter_count:count,dimensions:{layers:64,heads:64,kv_heads:8},parameters_by_dtype:{BF16:100,F32:1},declared_context_length:262144,context_length:4096,concurrency_per_replica:4,memory_gb:{}}});
    const facts=nodes["model-key-facts"].textContent;
    assert.ok(facts.includes("Parameters "+expected));
    assert.match(facts,/Layers 64/);assert.match(facts,/Attention heads \/ KV heads 64 \/ 8/);
    assert.match(facts,/Checkpoint dtype BF16 \/ F32/);assert.match(facts,/Max context 262,144 tokens/);
    assert.match(nodes.workload.textContent,/4,096 context tokens/);
  }
  assert.match(template,/<details[^>]*><summary>More model information<\/summary>/);
  assert.match(template,/<details id="sizing-details"[^>]*><summary>How GPU sizing uses this budget<\/summary><div id="memory-status">/);
});
test("replica totals include active ranks only and missing rank estimates stay unknown", () => {
  const row=option("region");row.allocation={...row.allocation,tensor_parallel_size:1,pipeline_parallel_size:7,required_gpus_per_replica:7,gpus_per_host:2,required_hosts:14,allocated_gpus:28,replicas:2,replicas_per_host:1,unused_gpus:14};row.memory_gb.estimated_per_gpu=18;
  const {nodes}=execute({options:{row}});
  assert.match(nodes.options.children[0].children[0].textContent,/126 GB Total memory \/ replica/);
  assert.match(nodes.options.textContent,/Spare GPUs · allocated, unassigned 14/);
  assert.doesNotMatch(nodes.options.textContent,/replicas per host/);
  assert.match(nodes.options.textContent,/14 Hosts · total|Hosts · total 14/);
  row.memory_gb.estimated_per_gpu=null;
  const unknown=execute({options:{row}}).nodes.options.children[0].children[0].textContent;
  assert.match(unknown,/Unknown Total memory \/ replica/);
});
test("different topology or serving images never share a GPU card", () => {
  const a=option("region-a"),b=option("region-b"),c=option("region-c");
  b.allocation={...b.allocation,tensor_parallel_size:2,pipeline_parallel_size:2};
  c.serving={...c.serving,image:"docker.io/vllm/vllm-openai@sha256:different"};
  assert.equal(execute({options:{a,b,c}}).nodes.options.children.length,3);
});
test("efficient allocations precede wasteful layouts regardless of option ID or AD", () => {
  const efficient=option("region-z"),wasteful=option("region-a");
  efficient.gpu_shape=wasteful.gpu_shape="VM.GPU.A10.2";
  efficient.allocation={...efficient.allocation,tensor_parallel_size:2,pipeline_parallel_size:3,required_gpus_per_replica:6,gpus_per_host:2,required_hosts:6,allocated_gpus:12,unused_gpus:0};
  wasteful.allocation={...efficient.allocation,tensor_parallel_size:1,pipeline_parallel_size:7,required_gpus_per_replica:7,required_hosts:14,allocated_gpus:28,unused_gpus:14};
  const {nodes}=execute({options:{aaa:wasteful,zzz:efficient}});
  assert.match(nodes.options.children[0].children[0].textContent,/2 × 3 TP × PP/);
  assert.match(nodes.options.children[1].children[0].textContent,/1 × 7 TP × PP/);
});
test("capacity sorting uses one AD and never sums locations", () => {
  const a=option("region-a"),b=option("region-b"),c=option("region-c");
  a.capacity.ad_available_gpus=b.capacity.ad_available_gpus=60;
  c.capacity.ad_available_gpus=100;c.gpu_shape="GPU.other";
  const {nodes}=execute({options:{a,b,c}});nodes.sort.value="capacity";nodes.sort.events.change();
  assert.match(nodes.options.children[0].children[0].textContent,/GPU.other/);
  assert.equal(nodes.options.children.length,2);
});
