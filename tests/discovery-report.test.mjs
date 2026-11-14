// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const template = readFileSync(new URL("../modules/discovery/discovery-report/report.html.tftpl", import.meta.url), "utf8");
const script = [...template.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)].at(-1)[1];
class Element {
  constructor(tag) { this.tag = tag; this.children = []; this.events = {}; this.value = ""; this._text = ""; }
  set textContent(value) { this._text = String(value); this.children = []; }
  get textContent() { return this._text + this.children.map((child) => child.textContent).join(" "); }
  set innerHTML(_) { throw new Error("Untrusted report values must never become HTML"); }
  appendChild(child) { this.children.push(child); return child; }
  replaceChildren(...children) { this.children = children; }
  addEventListener(event, callback) { this.events[event] = callback; }
}
function option(region) {
  return {
    region, availability_domain: "AD-1", gpu_shape: "GPU.8",
    capacity: { ad_available_hosts: 17, ad_available_gpus: 136, regional_available_gpus: 160, regional_known_reported_gpus: 160, regional_coverage: "complete", entitled_hosts: 2, observed_at: "scan-time" },
    allocation: { required_gpus_per_replica: 4, tensor_parallel_size: 4, pipeline_parallel_size: 1, required_hosts: 1, allocated_gpus: 8, replicas: 2, replicas_per_host: 2, unused_gpus: 0 },
    memory_gb: { per_gpu: 40, estimated_per_gpu: 30 }, memory_method: "analytical_requires_validation", configuration_status: "suggested_requires_validation", runtime_validation: "not_run", components: ["prometheus"], integration_requirements: [],
    links: { launch_url: "https://cloud.oracle.com/resourcemanager/stacks/create?region=" + region, download_url: "https://objectstorage.example/" + region + ".zip", expires_at: "expiry-time" },
  };
}
function execute(overrides = {}) {
  const report = {
    model: { repository: "org/model", revision: "pinned", context_length: 4096, concurrency_per_replica: 4, memory_gb: { checkpoint_download: 4, resident_weights: 4, kv_per_replica: null, total_estimated: null }, memory_status: "unsupported", memory_reasons: ["No estimator"] },
    scan: { assessed_regions: ["eu-frankfurt-1", "us-chicago-1"] }, option_count: 2, recommended_option_id: "first", failure_summary: [], notices: ["Counts are a snapshot"],
    options: { first: option("eu-frankfurt-1"), second: option("us-chicago-1") }, ...overrides,
  };
  const nodes = Object.fromEntries(["report-data", "model", "scan", "metrics", "failures", "notices", "search", "sort", "options"].map((id) => [id, new Element("div")]));
  nodes["report-data"].textContent = JSON.stringify(report);
  nodes.sort.value = "region";
  const created = [];
  const document = { getElementById: (id) => nodes[id], createElement: (tag) => { const node = new Element(tag); created.push(node); return node; } };
  const context = { document, URL };
  vm.runInNewContext(script, context, { timeout: 1000 });
  return { nodes, created, context };
}
test("comparison page shows all option links, counts, packing and unknown memory", () => {
  const { nodes, created } = execute();
  assert.equal(nodes.options.children.length, 2);
  assert.equal(created.filter((node) => node.tag === "a").length, 4);
  assert.match(nodes.options.textContent, /136 GPUs \/ 17 hosts/);
  assert.match(nodes.options.textContent, /160 GPUs/);
  assert.match(nodes.options.textContent, /4 GPUs \/ replica/);
  assert.match(nodes.options.textContent, /2 replicas; 2 per host/);
  assert.match(nodes.options.textContent, /expiry-time/);
  assert.match(nodes.metrics.textContent, /KV cache \/ replica Unknown/);
  nodes.search.value = "frankfurt";
  nodes.search.events.input();
  assert.equal(nodes.options.children.length, 1);
  assert.match(nodes.options.textContent, /eu-frankfurt-1/);
});
test("untrusted metadata is text and unsafe link schemes are rejected", () => {
  const malicious = "</script><script>globalThis.injected=true</script>";
  const unsafe = option(malicious);
  unsafe.links = { launch_url: "javascript:globalThis.injected=true", download_url: "data:text/html,unsafe", expires_at: null };
  const { nodes, created, context } = execute({ options: { unsafe }, option_count: 1 });
  assert.match(nodes.options.textContent, /<\/script><script>/);
  assert.equal(context.injected, undefined);
  assert.equal(created.filter((node) => ["script", "a"].includes(node.tag)).length, 0);
  assert.doesNotMatch(template, /\binnerHTML\b/);
});
