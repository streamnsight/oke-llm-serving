# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12", configuration_aliases = [oci.home] } }
}
locals {
  selection = var.model.selection
  profile   = var.model.profile
  serving   = merge(try(var.model.serving_configuration, {}), try(local.selection.serving_configuration, {}), { engine = try(local.selection.serving_configuration.engine, local.selection.engine, var.model.serving_configuration.engine, {}) })
  name      = coalesce(var.name, "model-${substr(sha256(var.model.model.repository), 0, 10)}")
  namespace = coalesce(var.namespace, "${var.platform.platform_name}-model-${substr(sha256(local.name), 0, 12)}")
  identity  = "model-${substr(sha256("${var.platform.cluster_id}/${local.namespace}/${local.name}"), 0, 24)}"
  owner     = sha256("${var.platform.platform_name}/${var.platform.cluster_id}/${local.namespace}/${local.name}")
  defaults = {
    MODEL_NAMESPACE     = local.namespace
    MODEL_CLUSTER_ID    = var.platform.cluster_id
    MODEL_PLATFORM_NAME = var.platform.platform_name
    MODEL_PROJECT_ID    = var.platform.project_id
    MODEL_GPU_POOL_ID   = try(coalesce(var.platform.allocation.gpu_pool_id, "runtime"), "runtime")
    MODEL_ID            = coalesce(var.overrides.model_id, try(local.serving.model.repository, null), var.model.model.repository)
    MODEL_REVISION      = coalesce(var.overrides.model_revision, try(local.serving.model.resolved_revision, null), try(var.model.model.revision, null), "unresolved")
    SERVING_IMAGE       = coalesce(var.overrides.serving_image, try(local.serving.engine.image, null), "unresolved")
    TP                  = tostring(coalesce(var.overrides.tensor_parallel_size, try(local.selection.tensor_parallel_size, null), 1))
    PP                  = tostring(coalesce(var.overrides.pipeline_parallel_size, try(local.selection.pipeline_parallel_size, null), 1))
    HOSTS_PER_REPLICA   = tostring(coalesce(var.overrides.hosts_per_replica, try(local.selection.pipeline_parallel_size, null), 1))
    GPUS_PER_POD        = tostring(coalesce(var.overrides.gpus_per_pod, try(local.selection.tensor_parallel_size, null), 1))
    REPLICAS            = tostring(coalesce(var.overrides.replicas, try(local.selection.replicas, null), 1))
    CONTEXT_LENGTH      = tostring(coalesce(var.overrides.context_length, try(local.profile.memory.assumptions.context_length, null), 4096))
    CONCURRENCY         = tostring(coalesce(var.overrides.concurrency, try(local.profile.memory.assumptions.concurrency, null), 1))
    INFERENCE_PROBE     = var.inference_probe
    MIN_REPLICAS        = tostring(var.autoscaling.min_replicas)
    MAX_REPLICAS        = tostring(var.autoscaling.max_replicas)
    TARGET_INFLIGHT     = tostring(var.autoscaling.target_inflight)
    PROMETHEUS_URL      = var.autoscaling.prometheus_url == "" ? "not-configured" : var.autoscaling.prometheus_url
  }
  # This is a full snapshot PER POD: packed replicas do not share emptyDir.
  snapshot_bytes = try(coalesce(var.model.model.checkpoint_download_bytes, try(local.profile.weights.total_file_bytes, null)), null)
  workspace_gib  = coalesce(var.storage.workspace_gib, local.snapshot_bytes == null ? 64 : ceil(local.snapshot_bytes * 1.15 / pow(1024, 3)) + 8)
  selector       = { (split("=", var.platform.gpu_selector)[0]) = split("=", var.platform.gpu_selector)[1] }
  router_enabled = var.router_enabled || tonumber(local.defaults.REPLICAS) > 1 || (var.autoscaling.enabled && var.autoscaling.max_replicas > 1)
  chart_sources  = { for asset in fileset("${path.module}/chart", "**") : asset => file("${path.module}/chart/${asset}") }
  chart_version  = "0.1.0-src-${substr(sha256(jsonencode({ files = local.chart_sources, router_sha256 = "6d03d2f28c34a7a2d05da62d3df44e349d662424e947f240b343a97f24f99c3c" })), 0, 12)}"
  chart_files = merge(local.chart_sources, {
    "Chart.yaml" = yamlencode({ apiVersion = "v2", name = "oke-llm-model", type = "application", version = local.chart_version,
      dependencies = [{ name = "vllm-stack", version = "0.1.14", repository = "https://vllm-project.github.io/production-stack", condition = "router.enabled" }]
    })
  })
  values = {
    identity       = local.identity, model = "$${MODEL_ID}", revision = "$${MODEL_REVISION}", image = "$${SERVING_IMAGE}",
    tensorParallel = "$${TP}", pipelineParallel = "$${PP}", hosts = "$${HOSTS_PER_REPLICA}", gpusPerPod = "$${GPUS_PER_POD}",
    replicas       = "$${REPLICAS}", contextLength = "$${CONTEXT_LENGTH}", concurrency = "$${CONCURRENCY}",
    recipeArgs     = try(local.serving.recipe.args, []), recipeEnv = try(local.serving.recipe.env, {}),
    nodeSelector   = local.selector, cpu = "2", memory = "16Gi", shm = "8Gi", workspace = "${local.workspace_gib}Gi",
    hfTokenSecret  = var.hf_token_secret, pvcName = var.storage.pvc_name,
    modelPath      = var.storage.mode == "direct_hf" ? "" : var.storage.model_path,
    rdmaResource   = try(var.platform.transport.requires_rdma, false) ? try(var.platform.transport.rdma_resource_name, "") : "",
    router         = { enabled = local.router_enabled },
    monitoring     = { enabled = try(var.platform.monitoring_enabled, false) || try(var.platform.autoscaling_enabled, false), platform = var.platform.platform_name },
    autoscaling    = merge(var.autoscaling, { min_replicas = "$${MIN_REPLICAS}", max_replicas = "$${MAX_REPLICAS}", target_inflight = "$${TARGET_INFLIGHT}", prometheus_url = "$${PROMETHEUS_URL}" }),
    "vllm-stack" = {
      servingEngineSpec = { enableEngine = false, modelSpec = [] },
      routerSpec = {
        enableRouter      = true, serviceAccountName = "oke-llm-router", serviceDiscovery = "k8s", k8sServiceDiscoveryType = "pod-ip",
        routingLogic      = "prefixaware", replicaCount = 1, serviceType = "ClusterIP",
        repository        = "lmcache/lmstack-router", tag = "v0.1.14@sha256:7107e6a17740478749ef28c812df48f405ccfab8d92f40372a50ef678b6c6b63",
        extraArgs         = ["--k8s-label-selector", "oke-llm/model=${local.identity},oke-llm/endpoint=true"],
        nodeSelectorTerms = [{ matchExpressions = [{ key = "nvidia.com/gpu.present", operator = "DoesNotExist" }, { key = "nvidia.com/gpu", operator = "DoesNotExist" }, { key = "oke-llm/allocation", operator = "DoesNotExist" }] }]
      },
      cacheserverSpec         = { enabled = false }, loraController = { enableLoraController = false },
      sharedPvcStorage        = { enabled = false }, grafanaDashboards = { enabled = false },
      "kube-prometheus-stack" = { enabled = false }, "prometheus-adapter" = { enabled = false }, "k8s-aibom" = { enabled = false }
    }
  }
  config = {
    platform          = var.platform, model = var.model, serving = local.serving, namespace = local.namespace, release = local.name,
    identity          = local.identity, ownership_token = local.owner, defaults = local.defaults,
    storage           = merge(var.storage, { workspace_gib = local.workspace_gib, snapshot_bytes = local.snapshot_bytes, workspace_explicit = var.storage.workspace_gib != null }),
    hf_token_secret   = var.hf_token_secret,
    router_enabled    = local.router_enabled, autoscaling = var.autoscaling, inference_probe = var.inference_probe,
    benchmark_backend = var.benchmark_backend, timeout_seconds = var.timeout_seconds,
    benchmark_image   = "vllm/vllm-openai-cpu@sha256:827ef38187f9b52f2bb838695ef815ec5b65f4bf3e4c061b002b2b0a19cb0701"
  }
  runtime_files = merge({ for asset in ["preflight.sh", "validate.sh", "retired.sh", "common.sh"] : asset => file("${path.module}/scripts/${asset}") }, { "config.json" = jsonencode(local.config) })
}
resource "terraform_data" "contract" {
  input = local.config
  lifecycle {
    precondition {
      condition     = startswith(local.namespace, "${var.platform.platform_name}-model-") && length(local.namespace) <= 63
      error_message = "Use the expected platform namespace prefix; trusted onboarding must authorize these exact independent-project pipeline IDs before execution."
    }
    precondition {
      condition     = can(regex("@sha256:[a-f0-9]{64}$", local.defaults.SERVING_IMAGE)) && can(regex("^[a-f0-9]{40}$", local.defaults.MODEL_REVISION))
      error_message = "Serving image must be digest-pinned and model revision must be an immutable Hugging Face commit."
    }
    precondition {
      condition     = local.snapshot_bytes == null ? true : local.workspace_gib >= ceil(local.snapshot_bytes / pow(1024, 3)) && local.snapshot_bytes > 0
      error_message = "Workspace must hold one full snapshot PER POD. Unknown size allows pipeline creation but requires an explicit expert budget before execution."
    }
    precondition {
      condition     = !var.autoscaling.enabled || (try(var.platform.autoscaling_enabled, false) && contains(var.platform.required_components, "prometheus") && contains(var.platform.required_components, "keda") && var.autoscaling.prometheus_url != "")
      error_message = "Model autoscaling requires existing KEDA/Prometheus controllers and an explicit reachable Prometheus URL."
    }
  }
}
module "delivery" {
  source                        = "../../shared/component-delivery"
  project_id                    = var.platform.project_id
  compartment_id                = var.compartment_id
  cluster_deploy_environment_id = var.platform.deploy_environment_id
  cluster_id                    = var.platform.cluster_id
  region                        = var.platform.region
  subnet_id                     = var.platform.runner_subnet_id
  nsg_ids                       = var.platform.runner_nsg_ids
  name                          = local.identity
  source_repository_id          = var.platform.script_repository_id
  result_repository_id          = var.platform.result_repository_id
  helm_version                  = "v3.19.2"
  runtime_files                 = local.runtime_files
  components = {
    workload = {
      mode                   = "managed", namespace = local.namespace, release_name = local.name, ownership_token = local.owner,
      namespace_mode         = "existing", lock_namespace = local.namespace, manage_crds = false,
      chart                  = { name = "oke-llm-model", version = local.chart_version, files = local.chart_files },
      values_yaml            = yamlencode(local.values), parameters = local.defaults,
      non_release_parameters = ["INFERENCE_PROBE"],
      deployment_names       = concat(tonumber(local.defaults.HOSTS_PER_REPLICA) == 1 ? [local.name] : [], local.router_enabled ? ["${local.name}-deployment-router"] : []),
      timeout_seconds        = var.timeout_seconds
    }
  }
  depends_on = [terraform_data.contract]
}
