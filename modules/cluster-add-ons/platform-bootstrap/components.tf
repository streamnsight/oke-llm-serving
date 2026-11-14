# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
locals {
  # Chart versions freeze a platform recommendation. Images come from the chart;
  # they are not duplicated or inferred from the model's serving image.
  chart_defaults      = jsondecode(file("${path.module}/data/components.json"))
  monitoring_enabled  = try(var.config.monitoring_enabled, true)
  autoscaling_enabled = try(var.config.autoscaling_enabled, false)
  cpu_affinity = { nodeAffinity = { requiredDuringSchedulingIgnoredDuringExecution = { nodeSelectorTerms = [{ matchExpressions = [
    { key = "nvidia.com/gpu", operator = "DoesNotExist" },
    { key = "oci.oraclecloud.com/gpu-shape", operator = "DoesNotExist" },
    { key = "nvidia.com/gpu.present", operator = "NotIn", values = ["true"] },
    { key = "feature.node.kubernetes.io/pci-10de.present", operator = "NotIn", values = ["true"] }
  ] }] } } }
  modes    = merge({ lws = "managed", prometheus = "managed", keda = "managed" }, try(var.config.component_modes, {}))
  required = { lws = try(var.config.enable_lws, false), prometheus = local.monitoring_enabled || local.autoscaling_enabled, keda = local.autoscaling_enabled }
  chart_specs = {
    lws = {
      chart            = { repository = "oci://registry.k8s.io/lws/charts", name = "lws", version = local.chart_defaults.lws.version }
      namespace        = "lws-system", release_name = "lws"
      crd_names        = ["leaderworkersets.leaderworkerset.x-k8s.io", "disaggregatedsets.disaggregatedset.x-k8s.io", "disaggregatedsetrolescalers.disaggregatedset.x-k8s.io"]
      blocker_kinds    = ["leaderworkersets.leaderworkerset.x-k8s.io", "disaggregatedsets.disaggregatedset.x-k8s.io", "disaggregatedsetrolescalers.disaggregatedset.x-k8s.io"]
      deployment_names = ["lws-controller-manager"]
      dependencies     = []
      parameters       = { CONTROLLER_CPU = "1", CONTROLLER_MEMORY = "1Gi" }
      values_yaml = yamlencode({
        enableDisaggregatedSet = try(var.config.enable_disaggregated_set, false),
        affinity               = local.cpu_affinity,
        resources              = { requests = { cpu = "$${CONTROLLER_CPU}", memory = "$${CONTROLLER_MEMORY}" } }
      })
    }
    prometheus = {
      chart            = { repository = "https://prometheus-community.github.io/helm-charts", name = "kube-prometheus-stack", version = local.chart_defaults.prometheus.version }
      namespace        = "monitoring", release_name = "llm-monitoring"
      crd_names        = ["prometheuses.monitoring.coreos.com", "servicemonitors.monitoring.coreos.com", "podmonitors.monitoring.coreos.com", "prometheusrules.monitoring.coreos.com"]
      blocker_kinds    = ["scaledobjects.keda.sh", "scaledjobs.keda.sh", "prometheuses.monitoring.coreos.com", "prometheusagents.monitoring.coreos.com", "alertmanagers.monitoring.coreos.com", "alertmanagerconfigs.monitoring.coreos.com", "thanosrulers.monitoring.coreos.com", "servicemonitors.monitoring.coreos.com", "podmonitors.monitoring.coreos.com", "probes.monitoring.coreos.com", "scrapeconfigs.monitoring.coreos.com", "prometheusrules.monitoring.coreos.com"]
      deployment_names = ["llm-monitoring-kube-prom-operator"]
      dependencies     = []
      parameters       = { PROMETHEUS_CPU = "1", PROMETHEUS_MEMORY = "2Gi", PROMETHEUS_RETENTION = "24h", PROMETHEUS_STORAGE = "50Gi", STORAGE_CLASS = "oci-bv" }
      values_yaml = yamlencode({
        fullnameOverride = "llm-monitoring-kube-prom",
        commonLabels     = { "oke-llm/platform" = var.name },
        grafana          = { enabled = false }, alertmanager = { enabled = false },
        nodeExporter     = { enabled = false }, kubeStateMetrics = { enabled = false },
        # Managed control-plane endpoints are not all exposed for scraping.
        kubeControllerManager = { enabled = false }, kubeScheduler = { enabled = false }, kubeEtcd = { enabled = false }, kubeProxy = { enabled = false },
        defaultRules          = { create = false },
        prometheusOperator    = { affinity = local.cpu_affinity, resources = { requests = { cpu = "200m", memory = "256Mi" } }, admissionWebhooks = { patch = { affinity = local.cpu_affinity } } },
        prometheus = { prometheusSpec = {
          affinity  = local.cpu_affinity, replicas = 1, retention = "$${PROMETHEUS_RETENTION}",
          resources = { requests = { cpu = "$${PROMETHEUS_CPU}", memory = "$${PROMETHEUS_MEMORY}" } },
          # Model monitors opt in with this label; unrelated tenants are not scraped.
          serviceMonitorSelectorNilUsesHelmValues = false, serviceMonitorSelector = { matchLabels = { "oke-llm/platform" = var.name } },
          podMonitorSelectorNilUsesHelmValues     = false, podMonitorSelector = { matchLabels = { "oke-llm/platform" = var.name } },
          serviceMonitorNamespaceSelector         = {}, podMonitorNamespaceSelector = {},
          persistentVolumeClaimRetentionPolicy    = { whenDeleted = "Retain", whenScaled = "Retain" },
          storageSpec                             = { volumeClaimTemplate = { spec = { storageClassName = "$${STORAGE_CLASS}", accessModes = ["ReadWriteOnce"], resources = { requests = { storage = "$${PROMETHEUS_STORAGE}" } } } } }
        } }
      })
    }
    keda = {
      chart            = { repository = "https://kedacore.github.io/charts", name = "keda", version = local.chart_defaults.keda.version }
      namespace        = "keda", release_name = "keda"
      crd_names        = ["scaledobjects.keda.sh", "scaledjobs.keda.sh", "triggerauthentications.keda.sh", "clustertriggerauthentications.keda.sh", "cloudeventsources.eventing.keda.sh", "clustercloudeventsources.eventing.keda.sh"]
      blocker_kinds    = ["scaledobjects.keda.sh", "scaledjobs.keda.sh", "triggerauthentications.keda.sh", "clustertriggerauthentications.keda.sh", "cloudeventsources.eventing.keda.sh", "clustercloudeventsources.eventing.keda.sh"]
      deployment_names = ["keda-operator", "keda-operator-metrics-apiserver", "keda-admission-webhooks"]
      dependencies     = []
      parameters       = { OPERATOR_CPU = "100m", OPERATOR_MEMORY = "256Mi" }
      values_yaml = yamlencode({
        affinity  = local.cpu_affinity,
        crds      = { additionalAnnotations = { "helm.sh/resource-policy" = "keep" } },
        resources = { operator = { requests = { cpu = "$${OPERATOR_CPU}", memory = "$${OPERATOR_MEMORY}" } }, metricServer = { requests = { cpu = "100m", memory = "256Mi" } }, webhooks = { requests = { cpu = "100m", memory = "128Mi" } } }
      })
    }
  }
  component_specs = { for key, spec in local.chart_specs : key => merge(spec, {
    mode = local.modes[key], ownership_token = sha256("${var.name}/${var.config.cluster_id}/${key}"), timeout_seconds = 900
  }, try(var.config.component_overrides[key], {})) if local.required[key] || local.modes[key] == "retire" }
  component_budget = {
    placement               = "existing_cluster_cpu_pools", creates_cpu_pool = false,
    cpu_requests_millicores = (local.required.lws ? 1000 : 0) + (local.required.prometheus ? 1200 : 0) + (local.required.keda ? 300 : 0),
    memory_requests_mib     = (local.required.lws ? 1024 : 0) + (local.required.prometheus ? 2304 : 0) + (local.required.keda ? 640 : 0),
    persistent_volume_gib   = local.required.prometheus ? 50 : 0,
    status                  = "baseline_requests_before_expert_overrides; allow rollout/headroom; actual scheduling validated by pipelines"
  }
}
module "components" {
  source                        = "../../shared/component-delivery"
  name                          = var.name
  project_id                    = oci_devops_project.platform.id
  compartment_id                = var.compartment_id
  cluster_deploy_environment_id = oci_devops_deploy_environment.cluster.id
  cluster_id                    = var.config.cluster_id
  region                        = var.config.region
  subnet_id                     = var.subnet_id
  nsg_ids                       = var.nsg_ids
  source_repository_id          = oci_artifacts_repository.scripts.id
  result_repository_id          = oci_artifacts_repository.results.id
  helm_version                  = local.chart_defaults.helm_version
  components                    = local.component_specs
}
