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
  constructor(tag) { this.tag = tag; this.children = []; this.events = {}; this.value = ""; this._text = ""; this.open = false; this.hidden = false; }
  set textContent(value) { this._text = String(value); this.children = []; }
  get textContent() { return this._text + this.children.map(child => child.textContent).join(" "); }
  set innerHTML(_) { throw new Error("Untrusted report values must never become HTML"); }
  appendChild(child) { this.children.push(child); return child; }
  replaceChildren(...children) { this.children = children; }
  addEventListener(event, callback) { this.events[event] = callback; }
}
function option(region) {
  return {
    region, availability_domain: "AD-1", gpu_shape: "GPU.8", gpu_type: "Test GPU",
    capacity: {ad_available_hosts: 17, ad_available_gpus: 136, regional_available_gpus: 160, regional_known_reported_gpus: 160, regional_coverage: "complete", entitled_hosts: 2, observed_at: "scan-time"},
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
    regional_capacity: [{region: "eu-frankfurt-1", gpu_shape: "GPU.8", gpus_per_host: 8, available_gpus: 136, available_hosts: 17, coverage: "complete", expected_ads: 1, known_ads: 1, limit_increase_possible: true, minimum_model_hosts: null, availability_domains: [{availability_domain: "AD-1", available_hosts: 17, entitled_hosts: 0, entitlement_status: "limit_increase_required", limit_increase_requests: [{limit_name: "gpu-count", current_limit: 0, scope: "AD", minimum_gpus_for_whole_hosts: null}]}]}], ...overrides,
  };
  const nodes = Object.fromEntries([...template.matchAll(/\bid="([^"]+)"/g)].map(match => [match[1], new Element("div")]));
  nodes["report-data"].textContent = JSON.stringify(report); nodes.sort.value = "region";
  const created = [], document = {getElementById: id => nodes[id], createElement: tag => {const node = new Element(tag); created.push(node); return node;}};
  const context = {document, URL}; vm.runInNewContext(script, context, {timeout: 1000});
  return {nodes, created, context};
}
test("option sections start collapsed and retain packing, both stack URLs and expiry", () => {
  const {nodes, created} = execute();
  assert.equal(nodes.options.children.length, 2);
  assert.ok(nodes.options.children.every(node => node.tag === "details" && !node.open));
  assert.match(nodes.options.textContent, /GPUs needed per replica/);
  assert.match(nodes.options.textContent, /replicas in 1 × 8-GPU hosts/);
  assert.match(nodes.options.textContent, /136 GPUs \/ 17 hosts/);
  assert.match(nodes.options.textContent, /expiry-time/);
  const hrefs = created.filter(node => node.tag === "a").map(node => node.href);
  for (const region of ["eu-frankfurt-1", "us-chicago-1"]) {
    assert.ok(hrefs.some(href => href.includes(region + "-model.zip")));
    assert.ok(hrefs.some(href => href.includes(region + "-infra.zip")));
    assert.ok(hrefs.some(href => href.includes("region=" + region + "&zipUrl=model")));
  }
  nodes.search.value = "frankfurt"; nodes.search.events.input();
  assert.equal(nodes.options.children.length, 1); assert.match(nodes.options.textContent, /eu-frankfurt-1/);
});
test("model metadata, unknown memory and limit review remain visible without options", () => {
  const {nodes} = execute({options: {}, option_count: 0, failure_summary: ["No confirmed serving layout"]});
  assert.match(nodes["model-details"].textContent, /Transformer layers 32/);
  assert.match(nodes["model-details"].textContent, /safetensors/);
  assert.match(nodes["memory-metrics"].textContent, /KV cache reservation \/ replica Unknown/);
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
  const {nodes} = execute();
  for (const option of nodes.options.children) {
    assert.ok(option.textContent.indexOf("Model project and pipelines") < option.textContent.indexOf("Serving configuration"));
  }
});
test("zero and unknown-only supply are hidden while positive supply with zero limits remains", () => {
  const positive = {region: "needs-limits", gpu_shape: "GPU", available_hosts: 3, available_gpus: 24, availability_domains: [{availability_domain: "AD",available_hosts: 3,entitled_hosts: 0}], limit_increase_possible: true};
  const {nodes} = execute({regional_capacity: [positive, {...positive,region:"zero",available_hosts:0,available_gpus:0}, {...positive,region:"unknown",available_hosts:null,available_gpus:null}]});
  assert.equal(nodes.capacity.children.length, 1);
  assert.match(nodes.capacity.textContent, /needs-limits/);
  assert.match(nodes.capacity.textContent, /Review limit increase/);
});
test("partial hybrid memory and planning budget have distinct labels", () => {
  const {nodes} = execute({model: {repository:"Qwen/model", context_length:4096,concurrency_per_replica:4,memory_status:"unsupported",memory_gb:{resident_weights:55.56,full_attention_kv:1.07,total_estimated:null},recipe_memory_budget_gb:71.83,partial_memory:{full_attention_layers:16,linear_attention_layers:48},planning_memory:{weight_bytes:55560000000,kv_surrogate_bytes:4290000000,safety_margin_fraction:0.2,recipe_minimum_bytes:67000000000,selected_payload_budget_bytes:71830000000,runtime_allowance_per_gpu_bytes:2147483648}}});
  assert.match(nodes["memory-metrics"].textContent, /Resident weights 55.56 GB/);
  assert.match(nodes["memory-metrics"].textContent, /Full-attention KV payload \/ replica 1.07 GB/);
  assert.match(nodes["memory-metrics"].textContent, /Planning payload budget \/ replica 71.83 GB/);
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
  assert.deepEqual(Object.keys(schema.outputs), ["comparison_report_url"]);
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
  assert.equal(infra.variables.autoscaling_enabled.default, false);
  assert.equal(model.variables.monitoring_enabled.default, true);
  assert.equal(model.variables.autoscaling_enabled.default, false);
  assert.ok(model.variables.storage_mode.enum.includes("staged_object_storage"));
});
