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
for (const [name, value] of [["Weight baseline (checkpoint precision)", model.memory_gb.resident_weights], [model.memory_gb.kv_per_replica == null && model.memory_gb.full_attention_kv != null ? "Full-attention KV payload / replica" : "KV cache reservation / replica", model.memory_gb.kv_per_replica ?? model.memory_gb.full_attention_kv], ["Runtime allowance / GPU", model.memory_gb.runtime_allowance], [model.component_planning?.payload_budget_bytes > 0 || (model.memory_gb.total_estimated == null && model.recipe_memory_budget_gb != null) ? "Planning payload budget / replica" : "Estimated total / replica", model.component_planning?.payload_budget_bytes > 0 ? Math.max(model.component_planning.payload_budget_bytes / 1e9, model.recipe_memory_budget_gb || 0) : model.memory_gb.total_estimated ?? model.recipe_memory_budget_gb]]) {
  const node = add($("memory-metrics"), "div", undefined, "metric"); add(node, "span", name); add(node, "strong", gb(value));
}
if (model.memory_status !== "estimated") {
  const note = add($("memory-status"), "div", undefined, "callout");
  add(note, "strong", model.component_planning?.payload_budget_bytes > 0 ? "Heuristic planning scenario available" : "Complete memory estimate unavailable");
  add(note, "p", (model.memory_reasons || []).join(" ") || "This model architecture does not yet have a complete memory estimator.");
  if (model.recipe_memory_budget_gb != null) add(note, "p", "Recipe-based aggregate sizing budget: " + gb(model.recipe_memory_budget_gb) + ". This is heuristic guidance; per-rank fit and runtime use remain unvalidated.");
  if (model.partial_memory?.linear_attention_layers > 0) add(note, "p", number(model.partial_memory.full_attention_layers) + " full-attention layers contribute the KV payload above. " + number(model.partial_memory.linear_attention_layers) + " linear-attention layers also need recurrent/cache state; cache-manager padding, cached state checkpoints and vision workspace are not included in that payload.");
}
if (model.planning_memory?.selected_payload_budget_bytes > 0) {
  const budget = model.planning_memory, explanation = details($("memory-status"), "How GPU sizing uses this budget", "recipe-details");
  facts(add(explanation, "dl", undefined, "facts"), [["Weights used in sizing", gb(budget.weight_bytes == null ? null : budget.weight_bytes / 1e9)], ["All-layer KV sizing surrogate", gb(budget.kv_surrogate_bytes == null ? null : budget.kv_surrogate_bytes / 1e9)], ["Recipe minimum", gb(budget.recipe_minimum_bytes == null ? null : budget.recipe_minimum_bytes / 1e9)], ["Payload safety margin", number(budget.safety_margin_fraction * 100) + "%"], ["Selected payload budget", gb(budget.selected_payload_budget_bytes / 1e9)], ["Additional runtime allowance per GPU", gb(budget.runtime_allowance_per_gpu_bytes / 1e9)]]);
  add(explanation, "p", "Sizing takes the largest of the recipe minimum, any supported analytical estimate, and (weights + all-layer KV surrogate) × (1 + margin). It divides that payload approximately across TP ranks, adds the runtime allowance per GPU, and checks against 90% of device memory. The all-layer surrogate treats every text layer as full attention; it is not an estimate of actual hybrid-cache allocation or a bound on recurrent/vision memory. Validation and benchmarking establish the real fit.");
}
if (model.component_planning?.payload_budget_bytes > 0) {
  const p = model.component_planning, box = details($("memory-status"), "Memory planning scenario and assumptions", "recipe-details");
  facts(add(box, "dl", undefined, "facts"), [["Planning payload / replica", gb(p.payload_budget_bytes / 1e9)], ["Cache scenario", gb(p.cache_scenario_bytes == null ? null : p.cache_scenario_bytes / 1e9)], ["Workspace allowance", gb(p.workspace_allowance_bytes == null ? null : p.workspace_allowance_bytes / 1e9)], ["Evidence / confidence", text(p.weight_source) + " / " + text(p.status)], ["Cache basis", text(p.cache_source)], ["Margin", number(p.safety_margin_fraction * 100) + "%"]]);
  add(box, "p", p.formula); add(box, "p", p.interpretation);
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
function limitSummary(limits, field) {
  return limits.length ? limits.map(limit => limitScope(limit) + ": " + limitQuantity(limit, field)).join("; ") : "Unknown";
}
function renderOptions() {
  const filter = $("search").value.toLowerCase(), mode = $("sort").value;
  const rows = Object.entries(report.options).filter(([id, row]) => [id, row.region, row.availability_domain, row.gpu_shape].join(" ").toLowerCase().includes(filter));
  rows.sort((a, b) => {
    if (mode === "allocated") return (a[1].allocation.allocated_gpus ?? Infinity) - (b[1].allocation.allocated_gpus ?? Infinity) || a[0].localeCompare(b[0]);
    if (mode === "capacity") return (b[1].capacity.ad_available_gpus ?? -1) - (a[1].capacity.ad_available_gpus ?? -1) || a[0].localeCompare(b[0]);
    return [a[1].region, a[1].gpu_shape, a[1].availability_domain, a[0]].join(" ").localeCompare([b[1].region, b[1].gpu_shape, b[1].availability_domain, b[0]].join(" "));
  });
  $("options").replaceChildren(); $("option-empty").hidden = rows.length > 0;
  $("option-count").textContent = number(rows.length) + " of " + number(report.option_count) + " options";
  const groups = new Map();
  for (const [id, row] of rows) {
    if (!groups.has(row.region)) {
      const group = add($("options"), "div", undefined, "region-group");
      add(group, "h3", row.region);
      groups.set(row.region, add(group, "div", undefined, "options"));
    }
    const a = row.allocation, c = row.capacity, serving = row.serving || {}, limits = c.limits || [];
    const option = add(groups.get(row.region), "details", undefined, "option");
    const summary = add(option, "summary"), title = add(summary, "div", undefined, "option-title");
    add(title, "strong", row.gpu_shape); add(title, "span", row.availability_domain, "muted oci-caption");
    if (id === report.recommended_option_id) add(title, "span", "Recommended starting point", "oci-status-active");
    if (row.runtime_validation !== "passed") badge(title, "Runtime unvalidated", true);
    const available = number(c.ad_available_gpus);
    for (const [value, caption] of [[available, "GPUs physically available in selected AD"], [number(a.required_gpus_per_replica), "GPUs needed per replica"], [number(a.replicas), "replicas in " + number(a.required_hosts) + " × " + number(a.gpus_per_host) + "-GPU hosts"]]) {
      const metric = add(summary, "div", undefined, "option-stat"); add(metric, "strong", value); add(metric, "span", caption);
    }
    const quota = add(summary, "div", undefined, "option-stat");
    add(quota, "strong", limitSummary(limits, "current_limit")); add(quota, "span", "Current configured limit");
    add(quota, "small", "Remaining headroom: " + limitSummary(limits, "remaining_headroom"));
    const body = add(option, "div", undefined, "option-body"), allocation = add(body, "section");
    add(allocation, "h3", "Allocation and replica packing");
    facts(add(allocation, "dl", undefined, "facts"), [["Shape / GPU type", row.gpu_shape + " / " + text(row.gpu_type)], ["Hosts / allocated GPUs", number(a.required_hosts) + " / " + number(a.allocated_gpus)], ["GPUs per replica · TP × PP", number(a.required_gpus_per_replica) + " · " + number(a.tensor_parallel_size) + " × " + number(a.pipeline_parallel_size)], ["Replicas / replicas per host", number(a.replicas) + " / " + number(a.replicas_per_host)], ["Unused GPUs", number(a.unused_gpus)], ["GPU memory per device", gb(row.memory_gb.per_gpu)], ["Estimated memory per rank", gb(row.memory_gb.estimated_per_gpu)], ["Transport", row.requires_rdma ? "RDMA required" : "Ethernet / within-host interconnect"]]);
    add(allocation, "p", "Selected AD: " + number(c.ad_available_gpus) + " GPUs / " + number(c.ad_available_hosts) + " hosts reported; entitlement covers " + number(c.entitled_hosts) + " hosts. Observed: " + text(c.observed_at) + ".", "muted");
    for (const limit of limits) {
      add(allocation, "p", text(limit.name) + " · " + limitScope(limit) + " · configured limit: " + limitQuantity(limit, "current_limit") + " · remaining compartment headroom: " + limitQuantity(limit, "remaining_headroom") + (limit.effective_quota == null ? "." : " · effective compartment quota: " + limitQuantity(limit, "effective_quota") + "."), "muted");
    }
    if (row.recommendation) {
      const r = row.recommendation;
      add(allocation, "p", "Growth at scan time: capacity and entitlement cover " + number(r.ad_max_replicas) + " replicas with this layout in the selected AD (" + number(r.ad_additional_replicas) + " beyond this allocation). RDMA capability: " + (r.rdma_capable ? "supported by the shape; fabric placement still requires validation" : "not established") + ". Supply and limits are shared snapshots, not future reservations.", "muted");
    }
    const steps = add(body, "div", undefined, "deployment-steps");
    deploymentStep(steps, "1. GPU pool and shared components", "Create this stack when you need a pool or shared controllers. Reuse an existing compatible platform for additional models.", row.links.launch_url, row.links.download_url, row.links.expires_at);
    const modelLinks = row.links.model_deployment || {};
    deploymentStep(steps, "2. Model project and pipelines", "Create an independent DevOps project for this model. Select the cluster; matching pool, networking and shared components are inferred. After infrastructure is ready, Apply runs namespace onboarding, deployment and validation. Benchmarking is manual.", modelLinks.launch_url, modelLinks.download_url, modelLinks.expires_at);
    const config = add(body, "section"); add(config, "h3", "Serving configuration"); badge(config, label(row.configuration_status), true);
    add(config, "p", "Runtime validation: " + label(row.runtime_validation) + ". Memory method: " + label(row.memory_method) + ".", "muted");
    facts(add(config, "dl", undefined, "facts"), [["Serving framework / version", text(serving.framework) + " / " + text(serving.version)], ["Container platform", serving.platform], ["Recipe GPU family", serving.source_hardware], ["Planned GPU family", serving.selected_hardware]]);
    add(config, "h4", "Serving image"); code(config, text(serving.image));
    const preview = plannedCommand(row);
    if (preview && serving.image) { add(config, "h4", "Planned engine command"); code(config, preview); }
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
function capacityQuantity(parent, value, unit, prefix = "") {
  const line = add(parent, "div");
  if (prefix) add(line, "span", prefix);
  const known = value != null && value !== "" && Number.isFinite(Number(value)) && value >= 0;
  add(line, known ? "strong" : "span", known ? number(value) : "Unknown");
  if (unit) add(line, "span", " " + unit);
}
function renderCapacity() {
  const filter = $("capacity-search").value.toLowerCase();
  const rows = (report.regional_capacity || []).flatMap(row => (row.availability_domains || [])
    .filter(ad => ad.available_hosts > 0).map(ad => ({row, ad})))
    .filter(({row, ad}) => [row.region, ad.availability_domain, row.gpu_shape].join(" ").toLowerCase().includes(filter));
  $("capacity").replaceChildren(); $("capacity-empty").hidden = rows.length > 0;
  for (const {row, ad} of rows) {
    const tr = add($("capacity"), "tr"), cells = Array.from({length: 5}, () => add(tr, "td"));
    add(cells[0], "strong", row.region + " " + ad.availability_domain);
    add(cells[0], "div", row.gpu_shape); add(cells[0], "small", gb(row.memory_gb_per_gpu) + " per GPU");
    const compatibility = row.dtype_compatibility || {status: "not_verified", reason: "Dtype compatibility not assessed."};
    badge(cells[0], compatibility.status === "compatible" ? "Dtype compatible" : compatibility.status === "not_compatible" ? "Not compatible" : "Not verified", compatibility.status !== "compatible");
    add(cells[0], "small", text(compatibility.required_precision) + ": " + text(compatibility.reason));
    capacityQuantity(cells[1], row.gpus_per_host, "");
    capacityQuantity(cells[2], row.gpus_per_host == null ? null : ad.available_hosts * row.gpus_per_host, "GPUs / " + number(ad.available_hosts) + " hosts physically available");
    add(cells[2], "small", number(row.known_ads) + " / " + number(row.expected_ads) + " ADs assessed");
    const limits = ad.limits || [];
    if (!limits.length) add(cells[3], "div", "Configured limit and headroom unknown");
    for (const limit of limits) {
      capacityQuantity(cells[3], limit.current_limit, text(limit.unit), limitScope(limit) + ": ");
      capacityQuantity(cells[3], limit.remaining_headroom, text(limit.unit), "Remaining headroom: ");
      add(cells[3], "small", limit.name);
    }
    if ((ad.limit_increase_requests || []).length) badge(cells[4], "Review limit increase", true);
    else add(cells[4], "div", "See AD entitlement");
    add(cells[4], "small", row.minimum_model_hosts == null ? "Model sizing unknown; validate before requesting limits." : "Aggregate-memory lower bound: " + number(row.minimum_model_hosts) + " hosts within one AD. Layout/runtime fit unvalidated.");
    const detail = details(cells[4], "AD capacity and limit details", "ad-details");
    add(detail, "p", number(ad.available_hosts) + " physical hosts · " + number(ad.entitled_hosts) + " entitled hosts · " + label(ad.entitlement_status));
    add(detail, "p", "Observed: " + text(ad.observed_at), "muted oci-caption");
    for (const request of ad.limit_increase_requests || []) add(detail, "p", "Review " + text(request.limit_name) + " (" + text(request.scope) + "), current limit " + number(request.current_limit) + (request.minimum_gpus_for_whole_hosts == null ? ". Model fit unknown." : "; aggregate whole-host lower bound " + number(request.minimum_gpus_for_whole_hosts) + " GPUs. Validate layout and runtime."));
  }
}
for (const notice of report.notices || []) add($("notices"), "li", notice);
$("search").addEventListener("input", renderOptions);
$("sort").addEventListener("change", renderOptions);
$("capacity-search").addEventListener("input", renderCapacity);
renderOptions(); renderCapacity();
