// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
"use strict";
const report = JSON.parse(document.getElementById("report-data").textContent);
const $ = id => document.getElementById(id);
const text = value => value === null || value === undefined || value === "" ? "Unknown" : String(value);
const label = value => text(value).replace(/_/g, " ");
const number = value => value === null || value === undefined || !Number.isFinite(Number(value)) ? "Unknown" : Number(value).toLocaleString(undefined, {maximumFractionDigits: 2});
const gb = value => value === null || value === undefined ? "Unknown" : number(value) + " GB";
const positive = value => Number(value) > 0 ? number(value) : "Unknown";
function parameters(value) {
  if (!(value > 0)) return "Unknown";
  for (const [size, suffix] of [[1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "K"]]) {
    if (value >= size) return number(value / size) + suffix;
  }
  return number(value);
}
function replicaMemory(row) {
  const rank = row.memory_gb?.estimated_per_gpu, gpus = row.allocation?.required_gpus_per_replica;
  return Number.isFinite(rank) && rank > 0 && Number.isFinite(gpus) && gpus > 0 ? rank * gpus : null;
}
function el(tag, value, className) {
  const node = document.createElement(tag);
  if (value !== undefined) node.textContent = value;
  if (className) node.className = className;
  return node;
}
function add(parent, tag, value, className) { return parent.appendChild(el(tag, value, className)); }
function link(parent, title, value, primary = false) {
  if (!value) return;
  let url; try { url = new URL(value); } catch { return; }
  if (url.protocol !== "https:") return;
  const anchor = add(parent, "a", title, primary ? "action-primary" : "oci-link");
  anchor.href = url.href; anchor.target = "_blank"; anchor.rel = "noopener noreferrer";
}
function facts(parent, rows) {
  for (const [name, value] of rows) { const item = add(parent, "div"); add(item, "dt", name); add(item, "dd", text(value)); }
}
function badge(parent, value, warning = false) { return add(parent, "span", value, "badge" + (warning ? " badge-warning" : "")); }
function code(parent, value) { const block = add(parent, "pre", undefined, "command"); add(block, "code", value); }
function details(parent, title, className) { const node = add(parent, "details", undefined, className); add(node, "summary", title); return node; }
function list(parent, entries) { const node = add(parent, "ul"); for (const entry of entries) add(node, "li", entry); }
function shell(value) {
  const s = String(value);
  return /^[A-Za-z0-9_./:=@+,-]+$/.test(s) ? s : "'" + s.replace(/'/g, "'\"'\"'") + "'";
}
function command(argv, environment = {}) {
  const env = Object.entries(environment || {}).map(([key, value]) => key + "=" + value);
  const lines = env.length ? ["env " + env.map(shell).join(" ")] : [];
  let index = 0;
  if (argv[0] === "vllm" && argv[1] === "serve") { lines.push(argv.slice(0, 3).map(shell).join(" ")); index = 3; }
  while (index < argv.length) {
    let value = shell(argv[index++]);
    if (String(argv[index - 1]).startsWith("-") && !String(argv[index - 1]).includes("=") && index < argv.length && !String(argv[index]).startsWith("-")) value += " " + shell(argv[index++]);
    lines.push(value);
  }
  return lines.join(" \\\n  ");
}
function plannedCommand(row) {
  const a = row.allocation, model = report.model;
  if (!model.repository || !model.revision || !a.tensor_parallel_size || !a.pipeline_parallel_size || !model.context_length || !model.concurrency_per_replica) return null;
  const managed = new Set(["--model", "--revision", "--served-model-name", "--host", "--port", "--tensor-parallel-size", "-tp", "--pipeline-parallel-size", "-pp", "--max-model-len", "--max-num-seqs", "--distributed-executor-backend", "--nnodes", "--node-rank", "--master-addr", "--headless"]);
  const original = row.serving?.args || [], args = [];
  for (let i = 0; i < original.length; i++) {
    const flag = String(original[i]).split("=")[0];
    if (managed.has(flag)) { if (!String(original[i]).includes("=") && flag !== "--headless") i++; }
    else args.push(original[i]);
  }
  const argv = ["vllm", "serve", model.repository, ...args, "--revision", model.revision, "--served-model-name", model.repository, "--host", "0.0.0.0", "--port", "8000", "--tensor-parallel-size", a.tensor_parallel_size, "--pipeline-parallel-size", a.pipeline_parallel_size, "--max-model-len", model.context_length, "--max-num-seqs", model.concurrency_per_replica];
  if (a.pipeline_parallel_size > 1) argv.push("--distributed-executor-backend", "mp");
  return command(argv, row.serving?.environment);
}
const model = report.model;
$("model-title").textContent = text(model.repository);
$("report-subtitle").textContent = number(report.option_count) + " capacity-confirmed deployment " + (report.option_count === 1 ? "option" : "options") + " · " + number((report.scan.assessed_regions || []).length) + " regions assessed";
$("recommendation-policy").textContent = report.recommendation_policy?.description || "";
$("report-time").textContent = "Published: " + text(report.publication?.published_at) + " · Report and deployment links expire: " + text(report.publication?.expires_at);
link($("model-links"), "View pinned model on Hugging Face", model.huggingface_url);
const dimensions = model.dimensions || {};
const dtypes = Object.entries(model.parameters_by_dtype || {}).sort((a, b) => b[1] - a[1]).map(([dtype]) => dtype);
facts($("model-key-facts"), [
  ["Parameters", parameters(model.parameter_count)], ["Layers", positive(dimensions.layers)],
  ["Attention heads / KV heads", positive(dimensions.heads) + " / " + positive(dimensions.kv_heads)],
  ["Checkpoint dtype", dtypes.join(" / ") || text(model.memory_assumptions?.weight_dtype)],
  ["Max context", model.declared_context_length > 0 ? number(model.declared_context_length) + " tokens" : "Unknown"]
]);
facts($("model-details"), [
  ["Model type", text(model.model_type) + " · " + label(model.architecture)],
  ["Declared task", label(model.declared_pipeline)], ["Architecture", (model.architecture_classes || []).join(", ") || "Unknown"],
  ["Transformer layers", positive(dimensions.layers)], ["Attention heads / KV heads", positive(dimensions.heads) + " / " + positive(dimensions.kv_heads)],
  ["Head dimension / hidden size", positive(dimensions.head_dim) + " / " + positive(dimensions.hidden_size)],
  ["Parameters (Hub-published)", number(model.parameter_count)], ["Checkpoint download size", gb(model.memory_gb.checkpoint_download)],
  ["Checkpoint formats in repository", (model.checkpoint_formats || []).join(", ") || "Unknown"],
  ["Selected checkpoint", model.selected_checkpoint], ["Published tensor dtypes", Object.keys(model.parameters_by_dtype || {}).join(", ") || "Unknown"],
  ["Quantization", model.quantization ? Object.entries(model.quantization).filter(([key]) => ["quant_method", "bits", "weight_block_size", "activation_scheme", "group_size"].includes(key)).map(([key, value]) => key + ": " + JSON.stringify(value)).join(" · ") || "Declared; see pinned model configuration" : "Not declared"],
  ["Declared maximum context", positive(model.declared_context_length) + " tokens"], ["Library / license", text(model.library) + " / " + text(model.license)],
  ["Revision", model.revision], ["Last modified on Hugging Face", model.last_modified],
  ["Access", model.gated === true || model.gated === "auto" || model.gated === "manual" ? "Gated model · Hub access required" : model.gated === false ? "Public model" : "Unknown"],
]);
if (model.experts > 0) facts($("model-details"), [["Experts / active per token", number(model.experts) + " / " + number(model.experts_per_token)]]);
$("model-provenance").textContent = text(model.weights_source) + ". Checkpoint download size describes storage; it is separate from resident GPU memory.";
const cachedTokens = model.context_length > 0 && model.concurrency_per_replica > 0 ? model.context_length * model.concurrency_per_replica : null;
$("workload").textContent = number(model.context_length) + " context tokens × " + number(model.concurrency_per_replica) + " concurrent sequences per replica = " + number(cachedTokens) + " live cached tokens when all sequences reach the requested length.";
const budgets = [model.component_planning?.payload_budget_bytes / 1e9, model.recipe_memory_budget_gb, model.memory_gb.total_estimated].filter(value => Number.isFinite(value) && value > 0);
let cacheMetric = [model.memory_gb.kv_per_replica == null && model.memory_gb.full_attention_kv != null ? "Full-attention KV / replica" : "KV cache / replica", model.memory_gb.kv_per_replica ?? model.memory_gb.full_attention_kv];
if (cacheMetric[1] == null && Number.isFinite(model.component_planning?.cache_scenario_bytes) && model.component_planning.cache_scenario_bytes >= 0) {
  const source = model.component_planning.cache_source, allLayer = source === "all_layer_dense_surrogate_not_upper_bound";
  cacheMetric = [allLayer ? "KV planning / replica" : "Cache allowance / replica", model.component_planning.cache_scenario_bytes / 1e9, (allLayer ? "All-layer scenario" : source === "weight_fraction_uncalibrated" ? "Weight-based scenario" : "Planning scenario") + " · unvalidated"];
}
for (const [name, value, note] of [["Sizing budget / replica", budgets.length ? Math.max(...budgets) : null], ["Weights / replica", model.memory_gb.resident_weights], cacheMetric, ["Runtime / GPU", model.memory_gb.runtime_allowance]]) {
  const node = add($("memory-metrics"), "div", undefined, "metric"); add(node, "span", name); add(node, "strong", gb(value));
  if (note) add(node, "span", note);
}
if (model.memory_status !== "estimated") {
  const note = add($("memory-status"), "div", undefined, "callout");
  add(note, "strong", model.component_planning?.payload_budget_bytes > 0 ? "Heuristic planning scenario available" : "Complete memory estimate unavailable");
  add(note, "p", (model.memory_reasons || []).join(" ") || "This model architecture does not yet have a complete memory estimator.");
  if (model.recipe_memory_budget_gb != null) add(note, "p", "Recipe-based aggregate sizing budget: " + gb(model.recipe_memory_budget_gb) + ". This is heuristic guidance; per-rank fit and runtime use remain unvalidated.");
  if (model.partial_memory?.linear_attention_layers > 0) add(note, "p", number(model.partial_memory.full_attention_layers) + " full-attention layers contribute the KV payload above. " + number(model.partial_memory.linear_attention_layers) + " linear-attention layers also need recurrent/cache state; cache-manager padding, cached state checkpoints and vision workspace are not included in that payload.");
}
if (model.planning_memory?.selected_payload_budget_bytes > 0) {
  const budget = model.planning_memory, explanation = add($("memory-status"), "div");
  facts(add(explanation, "dl", undefined, "facts"), [["Weights used in sizing", gb(budget.weight_bytes == null ? null : budget.weight_bytes / 1e9)], ["All-layer KV sizing surrogate", gb(budget.kv_surrogate_bytes == null ? null : budget.kv_surrogate_bytes / 1e9)], ["Recipe minimum", gb(budget.recipe_minimum_bytes == null ? null : budget.recipe_minimum_bytes / 1e9)], ["Payload safety margin", number(budget.safety_margin_fraction * 100) + "%"], ["Selected payload budget", gb(budget.selected_payload_budget_bytes / 1e9)], ["Additional runtime allowance per GPU", gb(budget.runtime_allowance_per_gpu_bytes / 1e9)]]);
  add(explanation, "p", "Sizing takes the largest of the recipe minimum, any supported analytical estimate, and (weights + all-layer KV surrogate) × (1 + margin). It divides that payload approximately across TP ranks, adds the runtime allowance per GPU, and checks against 90% of device memory. The all-layer surrogate treats every text layer as full attention; it is not an estimate of actual hybrid-cache allocation or a bound on recurrent/vision memory. Validation and benchmarking establish the real fit.");
}
if (model.component_planning?.payload_budget_bytes > 0) {
  const p = model.component_planning, box = add($("memory-status"), "div");
  facts(add(box, "dl", undefined, "facts"), [["Planning payload / replica", gb(p.payload_budget_bytes / 1e9)], ["Cache scenario", gb(p.cache_scenario_bytes == null ? null : p.cache_scenario_bytes / 1e9)], ["Workspace component of uncertainty", gb(p.workspace_allowance_bytes == null ? null : p.workspace_allowance_bytes / 1e9)], ["Evidence / confidence", text(p.weight_source) + " / " + text(p.status)], ["Cache basis", text(p.cache_source)], ["Margin", number(p.safety_margin_fraction * 100) + "%"]]);
  add(box, "p", p.formula); add(box, "p", p.interpretation);
  if (p.storage_metadata_conflict) add(box, "p", "Tensor counts and complete shard sizes disagree; planning retains the larger storage baseline. Verify the selected checkpoint.");
  if (p.context_within_declared_maximum === false) add(box, "p", "Requested context exceeds the model's declared maximum; deployment requires an explicitly supported extension.");
}
const assumptions = model.memory_assumptions || {};
$("memory-assumptions").textContent = "Weight precision: " + text(assumptions.weight_dtype) + " · KV dtype: " + text(assumptions.kv_dtype) + " · Safety margin: " + (model.safety_margin_fraction == null ? "Unknown" : number(model.safety_margin_fraction * 100) + "%") + ". Estimates use decimal GB. " + (assumptions.prefix_sharing === false ? "No prefix-sharing savings assumed. " : "") + (assumptions.offload === false ? "No offload savings assumed. " : "") + "These values are estimates, not measured GPU usage.";
if (!report.option_count) {
  const note = add($("failures"), "div", undefined, "callout");
  add(note, "strong", "No deployable option was confirmed");
  add(note, "p", "Review the memory assessment and regional capacity/limit details below.");
  if ((report.failure_summary || []).length) list(details(note, "Assessment reasons", "recipe-details"), report.failure_summary);
}
function deploymentStep(parent, title, description, launch, download, expires) {
  const section = add(parent, "div"); add(section, "h4", title); add(section, "p", description);
  const actions = add(section, "div", undefined, "action-links");
  link(actions, "Create RMS stack", launch, true); link(actions, "Download ZIP (PAR)", download);
  if (launch || download) add(section, "p", "Links expire: " + text(expires), "muted oci-caption");
  else add(section, "p", "Stack links were not published for this assessment. Enable deployment ZIP publication and apply discovery to generate them.", "muted");
}
function limitScope(limit) {
  return limit.scope === "AD" ? "AD " + text(limit.availability_domain) : limit.scope === "REGION" ? "Region" : limit.scope === "GLOBAL" ? "Global" : "Unknown scope";
}
function limitQuantity(limit, field) {
  const value = limit[field];
  return (value == null || value < 0 ? "Unknown" : number(value)) + " " + text(limit.unit);
}
function quantity(parent, value, required = null) {
  const known = value != null && value !== "" && Number.isFinite(Number(value)) && value >= 0;
  const insufficient = known && required > 0 && value < required;
  const node = add(parent, known ? "strong" : "span", known ? number(value) : "Unknown", insufficient ? "insufficient" : undefined);
  if (insufficient) {
    node.title = "Below required allocation of " + number(required) + " GPUs";
    add(parent, "span", " (below required allocation of " + number(required) + " GPUs)", "sr-only");
  }
}
function limitSummary(parent, limits, field, selectedAD, required) {
  const summary = add(parent, "div", undefined, "quota-values");
  if (!limits.length) { add(summary, "span", "Unknown"); return; }
  limits.forEach((limit, index) => {
    if (index) add(summary, "span", "; ");
    if (limit.scope !== "AD" || limit.availability_domain !== selectedAD) add(summary, "span", limitScope(limit) + ": ");
    quantity(summary, limit[field], limit.unit === "GPUs" ? required : null);
    add(summary, "span", " " + text(limit.unit));
  });
}
const servingLayouts = report.serving_layouts || {
  aggregated: {title: "Combined prefill + decode", description: "Each instance handles prefill and decode. Whole-host packing can add complete replicas.", options: report.options || {}, recommended_option_id: report.recommended_option_id},
  disaggregated: {title: "Separate prefill / decode (P/D)", status: "not_assessed", reasons: ["P/D eligibility and its combined role capacity were not assessed in this report. Rerun discovery with the current stack."], options: {}}
};
const layoutIDs = ["aggregated", "disaggregated"];
let activeLayout = "aggregated";
function selectLayout(id, focus = false) {
  activeLayout = id;
  for (const layoutID of layoutIDs) {
    const tab = $("layout-tab-" + layoutID), selected = layoutID === id;
    tab.setAttribute("aria-selected", String(selected)); tab.tabIndex = selected ? 0 : -1;
    if (selected && focus) tab.focus();
  }
  $("layout-panel").setAttribute("aria-labelledby", "layout-tab-" + id);
  renderOptions();
}
for (const id of layoutIDs) {
  const tab = $("layout-tab-" + id);
  tab.addEventListener("click", () => selectLayout(id));
  tab.addEventListener("keydown", event => {
    let index = layoutIDs.indexOf(id);
    if (event.key === "ArrowRight") index = (index + 1) % layoutIDs.length;
    else if (event.key === "ArrowLeft") index = (index + layoutIDs.length - 1) % layoutIDs.length;
    else if (event.key === "Home") index = 0;
    else if (event.key === "End") index = layoutIDs.length - 1;
    else return;
    event.preventDefault(); selectLayout(layoutIDs[index], true);
  });
}
function optionGroups(rows) {
  const groups = new Map();
  for (const entry of rows) {
    const [, row] = entry;
    // Only location-specific evidence and links may differ inside one card.
    const {region, availability_domain, capacity, links, recommendation, ...configuration} = row;
    const key = JSON.stringify(configuration);
    if (!groups.has(key)) groups.set(key, {row, locations: []});
    groups.get(key).locations.push(entry);
  }
  return [...groups.values()];
}
function renderLocation(parent, id, row, recommended) {
  const c = row.capacity, a = row.allocation, limits = c.limits || [];
  const location = details(parent, "", "location");
  const summary = location.children[0];
  const title = add(summary, "div", undefined, "location-title");
  add(title, "strong", row.region); add(title, "span", row.availability_domain, "muted oci-caption");
  if (id === recommended) badge(title, "Recommended location");
  const physical = add(summary, "div", undefined, "option-stat");
  quantity(physical, c.ad_available_gpus, a.allocated_gpus); add(physical, "span", "GPUs available in AD");
  add(physical, "small", number(c.ad_available_hosts) + " hosts");
  const quota = add(summary, "div", undefined, "option-stat");
  add(quota, "span", "Limit"); limitSummary(quota, limits, "current_limit", row.availability_domain, a.allocated_gpus);
  const left = add(summary, "div", undefined, "option-stat");
  add(left, "span", "Headroom"); limitSummary(left, limits, "remaining_headroom", row.availability_domain, a.allocated_gpus);
  const content = add(location, "div", undefined, "location-body");
  const steps = add(content, "div", undefined, "deployment-steps");
  deploymentStep(steps, "1. GPU pool and shared components", "Create or reuse a compatible platform.", row.links.launch_url, row.links.download_url, row.links.expires_at);
  const modelLinks = row.links.model_deployment || {};
  deploymentStep(steps, "2. Model project and pipelines", "Apply runs onboarding, deployment and validation. Benchmarks are manual.", modelLinks.launch_url, modelLinks.download_url, modelLinks.expires_at);
  const evidence = details(content, "Capacity and limit details", "recipe-details");
  facts(add(evidence, "dl", undefined, "facts"), [["Observed", c.observed_at], ["Hosts covered by headroom", number(c.entitled_hosts)]]);
  for (const limit of limits) add(evidence, "p", text(limit.name) + " · " + limitScope(limit) + " · limit " + limitQuantity(limit, "current_limit") + " / left " + limitQuantity(limit, "remaining_headroom") + (limit.effective_quota == null ? "" : " · quota " + number(limit.effective_quota)));
  if (row.recommendation && row.serving_mode !== "disaggregated") {
    const r = row.recommendation;
    add(evidence, "p", "Growth at scan time: " + number(r.ad_max_replicas) + " replicas (" + number(r.ad_additional_replicas) + " additional).", "muted");
  }
}
function renderOptions() {
  const layout = servingLayouts[activeLayout] || {options: {}, status: "not_assessed", reasons: ["This serving layout has not been assessed."]};
  const allRows = Object.entries(layout.options || {}), pd = activeLayout === "disaggregated";
  const recommended = layout.recommended_option_id ?? (pd ? null : report.recommended_option_id);
  $("layout-description").textContent = layout.description || (pd ? "Separate prefill and decode instances, each holding the complete model." : "Each instance handles prefill and decode.");
  $("layout-status").replaceChildren();
  if ((layout.reasons || []).length || !allRows.length) {
    const note = add($("layout-status"), "div", undefined, "callout");
    add(note, "strong", allRows.length ? label(layout.status) : "No confirmed " + (pd ? "P/D" : "combined serving") + " option");
    if ((layout.reasons || []).length) list(note, layout.reasons);
    else add(note, "p", "Review memory sizing, capacity and limits below.");
  }
  $("recommendation-policy").hidden = pd;
  const filter = $("search").value.toLowerCase(), mode = $("sort").value;
  const rows = allRows.filter(([id, row]) => [id, row.gpu_type, row.region, row.availability_domain, row.gpu_shape].join(" ").toLowerCase().includes(filter));
  const groups = optionGroups(rows);
  const capacity = group => Math.max(-1, ...group.locations.map(([, row]) => row.capacity.ad_available_gpus ?? -1));
  const identity = row => [row.gpu_type, row.gpu_shape, row.allocation.tensor_parallel_size, row.allocation.pipeline_parallel_size].join(" ");
  groups.sort((a, b) => {
    if (mode === "capacity" && capacity(a) !== capacity(b)) return capacity(b) - capacity(a);
    if (mode !== "gpu" && mode !== "region") {
      for (const field of ["allocated_gpus", "unused_gpus", "required_hosts"]) {
        const delta = (a.row.allocation[field] ?? Infinity) - (b.row.allocation[field] ?? Infinity);
        if (delta) return delta;
      }
    }
    return identity(a.row).localeCompare(identity(b.row));
  });
  $("options").replaceChildren(); $("option-empty").hidden = groups.length > 0;
  $("option-count").textContent = number(groups.length) + " GPU " + (groups.length === 1 ? "option" : "options") + " · " + number(rows.length) + " " + (rows.length === 1 ? "location" : "locations");
  $("option-empty").textContent = allRows.length ? "No matching deployment options." : "No capacity-confirmed deployment options for this serving layout.";
  for (const group of groups) {
    const row = group.row, a = row.allocation, serving = row.serving || {};
    const option = add($("options"), "article", undefined, "option");
    const summary = add(option, "div", undefined, "option-summary"), title = add(summary, "div", undefined, "option-title");
    add(title, "h3", row.gpu_type || row.gpu_shape);
    add(title, "span", row.gpu_shape + " · " + gb(row.memory_gb.per_gpu) + " / GPU", "muted oci-caption");
    if (group.locations.some(([id]) => id === recommended)) add(title, "span", "Recommended starting point", "oci-status-active");
    if (row.runtime_validation !== "passed") badge(title, "Runtime unvalidated", true);
    const allocationLabel = (pd ? number(row.prefill_replicas) + " prefill + " + number(row.decode_replicas) + " decode" : number(a.replicas) + " " + (a.replicas === 1 ? "replica" : "replicas")) + " · " + number(a.required_hosts) + " " + (a.required_hosts === 1 ? "host" : "hosts");
    for (const [value, caption, detail] of [[number(a.required_gpus_per_replica), pd ? "GPUs used / role instance" : "GPUs used / replica"], [number(a.tensor_parallel_size) + " × " + number(a.pipeline_parallel_size), "TP × PP"], [gb(replicaMemory(row)), pd ? "Total memory / role instance (estimate)" : "Total memory / replica (estimate)"], [number(a.allocated_gpus), "GPUs allocated · total", allocationLabel]]) {
      const metric = add(summary, "div", undefined, "option-stat"); add(metric, "strong", value); add(metric, "span", caption);
      if (detail) add(metric, "small", detail);
    }
    const body = add(option, "div", undefined, "option-body");
    const allocation = details(body, pd ? "Allocation and role pools" : "Allocation and replica packing", "recipe-details allocation-details");
    const packing = a.pipeline_parallel_size > 1 ? ["Replicas", number(a.replicas)] : ["Replicas / replicas per host", number(a.replicas) + " / " + number(a.replicas_per_host)];
    facts(add(allocation, "dl", undefined, "facts"), [["Hosts · total", number(a.required_hosts)], ["GPUs / host", number(a.gpus_per_host)], pd ? ["Prefill / decode instances", number(row.prefill_replicas) + " / " + number(row.decode_replicas)] : packing, ["Spare GPUs · allocated, unassigned", number(a.unused_gpus)], ["Estimated memory / GPU", gb(row.memory_gb.estimated_per_gpu)], [pd ? "Total memory / role instance (estimate)" : "Total memory / replica (estimate)", gb(replicaMemory(row))], ["Transport", row.requires_rdma ? "RDMA required" : "Ethernet / within-host interconnect"]]);
    add(allocation, "p", pd ? number(row.prefill_replicas) + " prefill + " + number(row.decode_replicas) + " decode · " + number(a.allocated_gpus) + " GPUs allocated" : number(a.replicas) + " replicas · " + number(a.allocated_gpus) + " GPUs allocated", "muted oci-caption");
    add(allocation, "p", "Total memory = estimated memory per GPU × GPUs used per instance; includes runtime overhead. Spare GPUs are excluded.", "muted oci-caption");
    if (pd) add(allocation, "p", "Role pods request " + number((row.prefill_replicas + row.decode_replicas) * a.required_gpus_per_replica) + " GPUs across both pools.", "muted oci-caption");
    const locations = add(body, "section", undefined, "locations"); add(locations, "h4", "Available locations");
    group.locations.sort((a, b) => [a[1].region, a[1].availability_domain, a[0]].join(" ").localeCompare([b[1].region, b[1].availability_domain, b[0]].join(" ")));
    for (const [id, location] of group.locations) renderLocation(locations, id, location, recommended);
    if (pd && row.launch_variables) {
      const manual = details(body, "Settings for a manual ZIP upload", "recipe-details");
      add(manual, "p", "Both tabs reuse the same ZIPs. Launch links prefill these settings; packaged defaults describe combined serving.");
      code(manual, JSON.stringify(row.launch_variables, null, 2));
    }
    const config = details(body, "Serving configuration", "recipe-details"); badge(config, label(row.configuration_status), true);
    add(config, "p", "Runtime validation: " + label(row.runtime_validation) + ". Memory method: " + label(row.memory_method) + ".", "muted");
    facts(add(config, "dl", undefined, "facts"), [["Serving framework / version", text(serving.framework) + " / " + text(serving.version)], ["Container platform", serving.platform], ["Recipe GPU family", serving.source_hardware], ["Planned GPU family", serving.selected_hardware]]);
    if (row.cache_capabilities) {
      const capabilities = row.cache_capabilities, features = details(config, "Cache and routing compatibility", "recipe-details");
      for (const [title, feature] of (pd ? [["KV-aware routing", capabilities.routing?.kvaware]] : [["KV-aware routing", capabilities.routing?.kvaware], ["LMCache MP", capabilities.lmcache?.mp], ["In-process LMCache", capabilities.lmcache?.inprocess]])) {
        if (!feature) continue;
        add(features, "p", title + ": " + label(feature.status) + ".");
        if ((feature.reasons || []).length) list(features, feature.reasons);
      }
      add(features, "p", pd ? "This layout uses native KV transfer with LMCache disabled. Engine prefix caching can remain enabled; P/D does not require KV-aware routing. Image and runtime checks remain required." : "Prefix-aware routing uses request affinity; KV-aware routing needs actual cache residency. LMCache MP adds CPU offloading. Image and runtime checks remain required.", "muted");
    }
    add(config, "h4", "Serving image"); code(config, text(serving.image));
    const preview = pd ? null : plannedCommand(row);
    if (pd) add(config, "p", "Each role instance uses TP=" + number(a.tensor_parallel_size) + " and PP=1. Deployment supplies role-specific native NIXL transfer settings and the orchestrating router; transfer effectiveness is checked after serving starts.");
    else if (preview && serving.image) { add(config, "h4", "Planned engine command"); code(config, preview); }
    else add(config, "p", "No complete engine command is available for this option; expert configuration is required.");
    if (a.pipeline_parallel_size > 1) add(config, "p", "Multi-node execution also requires per-node ranks and leader addresses supplied by orchestration. This preview does not replace the leader/worker deployment.", "muted");
    if ((serving.original_argv || []).length) {
      const upstream = details(config, "Original upstream recipe command", "recipe-details");
      add(upstream, "p", "Recipe hardware: " + text(serving.source_hardware) + ". Its original TP/workload settings may differ from this planned option.", "muted");
      code(upstream, command(serving.original_argv, serving.original_environment));
    }
    link(config, "View recipe source", serving.source_url);
    add(config, "p", "Required shared components: " + ((row.components || []).map(label).join(", ") || "none declared") + ".", "muted");
    const requirements = [...(row.warnings || []), ...(row.deployment_requirements || []), ...(row.integration_requirements || []).map(label)];
    if (requirements.length) list(details(config, "Configuration notes and remaining checks", "recipe-details"), requirements);
    if ((serving.dependencies || []).length || (serving.companions || []).length) code(details(config, "Recipe dependency and companion details", "recipe-details"), JSON.stringify({dependencies: serving.dependencies || [], companions: serving.companions || []}, null, 2));
  }
}
function capacityQuantity(parent, value, unit, prefix = "", required = null) {
  const line = add(parent, "div");
  if (prefix) add(line, "span", prefix);
  quantity(line, value, required);
  if (unit) add(line, "span", " " + unit);
}
function renderCapacity() {
  const filter = $("capacity-search").value.toLowerCase();
  const rows = (report.regional_capacity || []).flatMap(row => (row.availability_domains || [])
    .filter(ad => ad.available_hosts > 0).map(ad => ({row, ad})))
    .filter(({row, ad}) => [row.region, ad.availability_domain, row.gpu_shape].join(" ").toLowerCase().includes(filter));
  $("capacity").replaceChildren(); $("capacity-empty").hidden = rows.length > 0;
  for (const {row, ad} of rows) {
    const tr = add($("capacity"), "tr"), cells = Array.from({length: 6}, () => add(tr, "td"));
    const required = row.minimum_model_hosts > 0 && row.gpus_per_host > 0 ? row.minimum_model_hosts * row.gpus_per_host : null;
    add(cells[0], "strong", row.region + " " + ad.availability_domain);
    add(cells[0], "div", row.gpu_shape); add(cells[0], "small", gb(row.memory_gb_per_gpu) + " per GPU");
    const compatibility = row.dtype_compatibility || {status: "not_verified", reason: "Dtype compatibility not assessed."};
    badge(cells[0], compatibility.status === "compatible" ? "Dtype compatible" : compatibility.status === "not_compatible" ? "Not compatible" : "Not verified", compatibility.status !== "compatible");
    add(cells[0], "small", text(compatibility.required_precision) + ": " + text(compatibility.reason));
    capacityQuantity(cells[1], row.minimum_model_gpus, "");
    add(cells[1], "small", "Memory lower bound / replica");
    if (required != null) add(cells[1], "small", "Allocate " + number(required) + " GPUs / " + number(row.minimum_model_hosts) + " hosts");
    capacityQuantity(cells[2], row.gpus_per_host, "");
    capacityQuantity(cells[4], row.gpus_per_host == null ? null : ad.available_hosts * row.gpus_per_host, "GPUs / " + number(ad.available_hosts) + " hosts physically available", "", required);
    add(cells[4], "small", number(row.known_ads) + " / " + number(row.expected_ads) + " ADs assessed");
    const limits = ad.limits || [];
    if (!limits.length) add(cells[3], "div", "Configured limit and headroom unknown");
    for (const limit of limits) {
      const amounts = add(cells[3], "div");
      add(amounts, "span", "limit ");
      quantity(amounts, limit.current_limit, limit.unit === "GPUs" ? required : null);
      add(amounts, "span", " / left ");
      quantity(amounts, limit.remaining_headroom, limit.unit === "GPUs" ? required : null);
      add(cells[3], "small", limitScope(limit) + " · " + text(limit.unit));
      add(cells[3], "small", limit.name);
    }
    if ((ad.limit_increase_requests || []).length) badge(cells[5], "Review limit increase", true);
    else add(cells[5], "div", "See AD entitlement");
    add(cells[5], "small", row.minimum_model_hosts == null ? "Model sizing unknown; validate before requesting limits." : "Aggregate-memory lower bound: " + number(row.minimum_model_hosts) + " hosts within one AD. Layout/runtime fit unvalidated.");
    const detail = details(cells[5], "AD capacity and limit details", "ad-details");
    add(detail, "p", number(ad.available_hosts) + " physical hosts · " + number(ad.entitled_hosts) + " entitled hosts · " + label(ad.entitlement_status));
    add(detail, "p", "Observed: " + text(ad.observed_at), "muted oci-caption");
    for (const request of ad.limit_increase_requests || []) add(detail, "p", "Review " + text(request.limit_name) + " (" + text(request.scope) + "), current limit " + number(request.current_limit) + (request.minimum_gpus_for_whole_hosts == null ? ". Model fit unknown." : "; aggregate whole-host lower bound " + number(request.minimum_gpus_for_whole_hosts) + " GPUs. Validate layout and runtime."));
  }
}
for (const notice of report.notices || []) add($("notices"), "li", notice);
$("search").addEventListener("input", renderOptions);
$("sort").addEventListener("change", renderOptions);
$("capacity-search").addEventListener("input", renderCapacity);
selectLayout("aggregated"); renderCapacity();
