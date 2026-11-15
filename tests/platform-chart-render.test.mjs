// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import YAML from "yaml";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const enabled = process.env.RUN_HELM_CHART_TESTS === "1";

function run(command, args, options = {}) {
  return execFileSync(command, args, {
    encoding: "utf8", timeout: 60_000, maxBuffer: 64 * 1024 * 1024,
    ...options,
  });
}

function documents(rendered) {
  return rendered.split(/^---\s*$/m).map((source) => {
    // Tests inspect CRD identity/retention, not thousands of upstream schema fields.
    const header = /^kind: CustomResourceDefinition\s*$/m.test(source)
      ? source.split(/^spec:\s*$/m, 1)[0]
      : source;
    return YAML.parse(header);
  }).filter(Boolean);
}

function assertCpuPlacement(affinity, name) {
  const terms = affinity?.nodeAffinity?.requiredDuringSchedulingIgnoredDuringExecution?.nodeSelectorTerms;
  assert.ok(terms?.length, `${name} must exclude GPU nodes`);
  const matches = (term, labels) => term.matchExpressions.every(({key, operator, values}) => {
    if (operator === "DoesNotExist") return !(key in labels);
    if (operator === "NotIn") return !(key in labels) || !values.includes(labels[key]);
    if (operator === "In") return key in labels && values.includes(labels[key]);
    throw Error(`Unexpected affinity operator ${operator}`);
  });
  assert.ok(terms.some(term => matches(term, {})), `${name} must admit CPU nodes without GPU labels`);
  for (const [label,value] of Object.entries({"nvidia.com/gpu":"8", "nvidia.com/gpu.present":"true", "oci.oraclecloud.com/gpu-shape":"BM.GPU.H100.8", "feature.node.kubernetes.io/pci-10de.present":"true"})) {
    assert.equal(terms.some(term => matches(term, {[label]:value})), false, `${name}: GPU label ${label}=${value} must exclude the node`);
  }
}

test("selected upstream charts render with the platform adapter values", {
  skip: !enabled && "Set RUN_HELM_CHART_TESTS=1 to download the selected upstream Helm charts; requires helm and terraform.",
  timeout: 240_000,
}, async (t) => {
  const directory = mkdtempSync(join(tmpdir(), "oke-platform-charts-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const moduleDirectory = join(root, "modules/cluster-add-ons/platform-bootstrap");
  const componentSource = readFileSync(join(moduleDirectory, "components.tf"), "utf8");
  const moduleStart = componentSource.indexOf('\nmodule "components"');
  assert.ok(moduleStart > 0, "Expected chart locals before the component-delivery module");
  mkdirSync(join(directory, "data"));
  copyFileSync(join(moduleDirectory, "data/components.json"), join(directory, "data/components.json"));
  writeFileSync(join(directory, "main.tf"), componentSource.slice(0, moduleStart));
  writeFileSync(join(directory, "variables.tf"), [
    'variable "name" { default = "chart-fixture" }',
    'variable "config" { default = { cluster_id="fixture", enable_lws=true, enable_disaggregated_set=true, monitoring_enabled=true, keda_enabled=true } }',
  ].join("\n"));
  // Evaluate the actual HCL adapters; do not duplicate Helm values in this test.
  const result = run("terraform", ["console"], { cwd: directory, input: "jsonencode(local.chart_specs)\n" }).trim();
  const specs = JSON.parse(JSON.parse(result));

  for (const [component, spec] of Object.entries(specs)) {
    await t.test(`${component}: published chart, CRDs, CPU placement and retained data`, () => {
      const componentDirectory = join(directory, component);
      mkdirSync(componentDirectory);
      const env = {
        ...process.env,
        HELM_CACHE_HOME: join(componentDirectory, "cache"),
        HELM_CONFIG_HOME: join(componentDirectory, "config"),
        HELM_DATA_HOME: join(componentDirectory, "data"),
      };
      const args = spec.chart.repository.startsWith("oci://")
        ? ["pull", `${spec.chart.repository}/${spec.chart.name}`]
        : ["pull", spec.chart.name, "--repo", spec.chart.repository];
      run("helm", [...args, "--version", spec.chart.version, "--destination", componentDirectory, "--untar"], { env });
      const chartDirectory = join(componentDirectory, spec.chart.name);
      const chart = YAML.parse(readFileSync(join(chartDirectory, "Chart.yaml"), "utf8"));
      assert.equal(chart.version.replace(/^v/, ""), spec.chart.version.replace(/^v/, ""));
      const values = spec.values_yaml.replace(/\$\{([A-Z_]+)\}/g, (_, key) => {
        assert.ok(Object.hasOwn(spec.parameters, key), `${component}: undeclared parameter ${key}`);
        return spec.parameters[key];
      });
      assert.doesNotMatch(values, /\$\{[A-Z_]+\}/);
      const valuesFile = join(componentDirectory, "values.yaml");
      writeFileSync(valuesFile, values);
      const templateArgs = ["template", spec.release_name, chartDirectory, "--namespace", spec.namespace,
        "--kube-version", "1.34.3", "--values", valuesFile];
      const rendered = documents(run("helm", [...templateArgs, "--include-crds"], { env }));
      const templated = documents(run("helm", templateArgs, { env }));
      const crds = rendered.filter((object) => object.kind === "CustomResourceDefinition");
      for (const name of spec.crd_names) {
        assert.ok(crds.some((object) => object.metadata.name === name), `${component}: declared CRD ${name} must exist in selected chart`);
      }
      for (const object of templated.filter((item) => ["CustomResourceDefinition", "PersistentVolumeClaim"].includes(item.kind))) {
        assert.equal(object.metadata.annotations?.["helm.sh/resource-policy"], "keep", `${component}: Helm-managed ${object.kind}/${object.metadata.name} must survive uninstall`);
      }
      for (const name of spec.deployment_names) {
        assert.ok(rendered.some((object) => object.kind === "Deployment" && object.metadata.name === name), `${component}: declared Deployment ${name} must exist`);
      }
      for (const object of rendered.filter((item) => ["Deployment", "Job"].includes(item.kind))) {
        assertCpuPlacement(object.spec.template.spec.affinity, `${component}/${object.metadata.name}`);
      }

      if (component === "lws") {
        for (const name of ["disaggregatedsets.disaggregatedset.x-k8s.io", "disaggregatedsetrolescalers.disaggregatedset.x-k8s.io"]) {
          assert.ok(crds.some((object) => object.metadata.name === name));
        }
        const webhooks = rendered.filter((object) => object.kind === "ValidatingWebhookConfiguration").flatMap((object) => object.webhooks);
        assert.ok(webhooks.some((webhook) => webhook.rules.some((rule) => rule.apiGroups.includes("disaggregatedset.x-k8s.io"))), "DisaggregatedSet must be enabled in chart webhooks");
      }
      if (component === "prometheus") {
        const prometheus = rendered.find((object) => object.kind === "Prometheus");
        assert.ok(prometheus, "The monitoring chart must deploy a Prometheus server, not only its operator");
        assertCpuPlacement(prometheus.spec.affinity, "Prometheus");
        assert.equal(prometheus.spec.storage.volumeClaimTemplate.spec.resources.requests.storage, spec.parameters.PROMETHEUS_STORAGE);
        assert.equal(prometheus.spec.storage.volumeClaimTemplate.spec.storageClassName, spec.parameters.STORAGE_CLASS);
        const retention = prometheus.spec.persistentVolumeClaimRetentionPolicy;
        assert.equal(retention?.whenDeleted ?? "Retain", "Retain");
        assert.equal(retention?.whenScaled ?? "Retain", "Retain");
        assert.equal(prometheus.spec.retention, spec.parameters.PROMETHEUS_RETENTION);
        const service = rendered.find((object) => object.kind === "Service" && object.metadata.name === prometheus.metadata.name);
        assert.ok(service.spec.ports.some((port) => port.port === 9090));
        const monitorSelector = prometheus.spec.serviceMonitorSelector.matchLabels;
        for (const monitor of rendered.filter((object) => object.kind === "ServiceMonitor")) {
          for (const [key, value] of Object.entries(monitorSelector)) assert.equal(monitor.metadata.labels[key], value, "Chart monitors must match the platform scrape selector");
        }
      }
      if (component === "keda") {
        assert.equal(crds.length, 6, "Selected KEDA release installs six CRDs, including event sources");
        const api = rendered.find((object) => object.kind === "APIService" && object.metadata.name === "v1beta1.external.metrics.k8s.io");
        assert.ok(api, "KEDA must register the external metrics API");
        assert.equal(api.spec.service.name, "keda-operator-metrics-apiserver");
        assert.equal(api.spec.service.namespace, spec.namespace);
        const service = rendered.find((object) => object.kind === "Service" && object.metadata.name === api.spec.service.name);
        assert.ok(service.spec.ports.some((port) => port.port === 443 && port.targetPort === 6443));
        assert.ok(service.spec.ports.some((port) => port.name === "metrics" && port.port === 8080));
      }
      t.diagnostic(`${component}: rendered published ${chart.name} ${chart.version}; no Kubernetes or OCI resources created`);
    });
  }
});
