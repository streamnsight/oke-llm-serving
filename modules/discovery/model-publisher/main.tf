# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    archive = { source = "hashicorp/archive", version = "~> 2.8" }
    oci     = { source = "oracle/oci", version = "~> 9.12" }
  }
}
locals {
  enabled      = var.model_spec != null && var.publication != null
  dependencies = toset(["llm-deployment/model-delivery", "shared/component-delivery"])
  module_files = local.enabled ? merge([for dependency in local.dependencies : {
    for relative in fileset("${var.modules_dir}/${dependency}", "**") : "modules/${dependency}/${relative}" => file("${var.modules_dir}/${dependency}/${relative}")
    if !startswith(relative, ".") && !startswith(relative, "tests/") && !startswith(relative, "work/") && !startswith(relative, "node_modules/") && !strcontains(relative, "/.") && !can(regex("\\.(tfstate(\\..*)?|tfvars(\\.json)?|tfplan)$", relative))
  }]...) : {}
  template_files = local.enabled ? {
    for relative in setunion(fileset(var.template_dir, "*.tf"), toset(["schema.yaml", ".terraform.lock.hcl"])) : relative => replace(file("${var.template_dir}/${relative}"), "../../modules/", "./modules/")
  } : {}
  schema         = yamldecode(local.enabled ? local.template_files["schema.yaml"] : "variables: {}")
  selected       = try(var.model_spec.selection, {})
  repository     = try(coalesce(try(var.model_spec.model.repository, null), try(var.model_spec.profile.model.repository, null)), "unselected/model")
  model_folder   = replace(replace(local.repository, "/", "--"), "/[^A-Za-z0-9_.-]/", "-")
  model_name     = "m-${substr(replace(lower(local.repository), "/[^a-z0-9-]/", "-"), 0, 13)}-${substr(sha256(local.repository), 0, 6)}"
  snapshot_bytes = try(coalesce(try(var.model_spec.model.checkpoint_download_bytes, null), try(var.model_spec.profile.weights.checkpoint_download_bytes, null)), null)
  recommendation = {
    model_name           = local.model_name, namespace = "${var.platform_binding.platform_name}-model-${local.model_name}",
    model_id             = local.repository, model_revision = try(coalesce(try(var.model_spec.model.revision, null), try(var.model_spec.profile.model.resolved_revision, null)), ""),
    serving_image        = try(coalesce(try(local.selected.serving_configuration.engine.image, null), try(local.selected.engine.image, null), try(var.model_spec.serving_configuration.engine.image, null)), ""),
    tensor_parallel_size = try(local.selected.tensor_parallel_size, 1), pipeline_parallel_size = try(local.selected.pipeline_parallel_size, 1),
    hosts_per_replica    = try(local.selected.hosts_per_replica, local.selected.pipeline_parallel_size, 1),
    gpus_per_pod         = try(local.selected.gpus_per_pod, local.selected.tensor_parallel_size, 1), replicas = try(local.selected.replicas, 1),
    context_length       = try(coalesce(try(var.model_spec.model.context_length, null), try(var.model_spec.profile.memory.assumptions.context_length, null)), 4096),
    concurrency          = try(coalesce(try(var.model_spec.model.concurrency, null), try(var.model_spec.profile.memory.assumptions.concurrency, null)), 1)
    storage_mode         = try(var.platform_binding.model_storage.mode == "object_storage", false) ? "staged_object_storage" : "direct_hf"
    workspace_gib        = local.snapshot_bytes == null ? 64 : max(20, ceil(local.snapshot_bytes * 2 / pow(1024, 3))),
    router_enabled       = try(local.selected.replicas > 1, false) || try(var.platform_binding.autoscaling_enabled, false),
    autoscaling_enabled  = try(var.platform_binding.autoscaling_enabled, false),
    min_replicas         = try(local.selected.requested_minimum_replicas, local.selected.replicas, 1),
    max_replicas         = try(local.selected.replicas, 1), prometheus_url = try(var.platform_binding.prometheus_url, null)
  }
  defaults      = { for key, value in local.recommendation : key => value if contains(keys(local.schema.variables), key) && (key != "workspace_gib" || local.snapshot_bytes != null) }
  template_hash = sha256(jsonencode({ template = local.template_files, modules = local.module_files }))
  header        = "# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.\n# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.\n"
  published_at  = local.enabled ? terraform_data.publication[0].output : ""
  run_id        = local.enabled ? substr(replace(terraform_data.publication[0].id, "-", ""), 0, 12) : ""
  filename      = local.enabled ? "model-${formatdate("YYYYMMDD'T'hhmmss'Z'", local.published_at)}-${local.run_id}-${substr(sha256(jsonencode(var.model_spec)), 0, 12)}.zip" : ""
  object_name   = "models/${local.model_folder}/${var.platform_binding.region}/${var.platform_binding.gpu_shape}/${local.filename}"
  launch_name   = "rms/${local.run_id}-${substr(sha256("model/${jsonencode(var.platform_binding)}"), 0, 16)}.zip"
  files = local.enabled ? merge(local.template_files, local.module_files, {
    "schema.yaml"                      = "${local.header}${yamlencode(merge(local.schema, { variables = { for key, value in local.schema.variables : key => merge(value, try({ default = local.defaults[key] }, {})) } }))}",
    "recommendations_override.tf.json" = jsonencode({ variable = { for key, value in local.defaults : key => { default = value } } }),
    "inputs/model-spec.json"           = jsonencode(var.model_spec), "inputs/platform-binding.json" = jsonencode(var.platform_binding),
    "LICENSE.txt"                      = file("${var.modules_dir}/../LICENSE.txt"),
    "bundle-manifest.json" = jsonencode({
      kind                    = "llm_deployment", schema_version = "1.0", expected_region = var.platform_binding.region, published_at = local.published_at,
      run_id                  = local.run_id, template_sha256 = local.template_hash, model_spec_sha256 = sha256(jsonencode(var.model_spec)),
      platform_binding_sha256 = sha256(jsonencode(var.platform_binding)), source_commit = try(var.model_spec.source_commit, null)
    })
  }) : {}
}
resource "terraform_data" "publication" {
  count            = local.enabled ? 1 : 0
  triggers_replace = uuid()
  input            = timestamp()
  lifecycle {
    precondition {
      condition     = try(var.platform_binding.schema_version == "1.0" && var.platform_binding.project_id != "" && var.platform_binding.deploy_environment_id != "" && var.platform_binding.script_repository_id != "" && var.platform_binding.result_repository_id != "", false)
      error_message = "Publish a model bundle only after the existing platform project, OKE deployment environment and artifact repositories are identified."
    }
    precondition {
      condition     = length(local.recommendation.namespace) <= 63 && can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", local.recommendation.namespace))
      error_message = "Generated model namespace must fit a Kubernetes DNS label."
    }
  }
}
# Resource rather than data source: Plan and Apply may run on different RMS workers.
resource "archive_file" "model" {
  count            = local.enabled ? 1 : 0
  type             = "zip"
  output_path      = "${path.root}/.generated/model-${substr(sha256(local.repository), 0, 16)}.zip"
  output_file_mode = "0644"
  dynamic "source" {
    for_each = local.files
    content {
      filename = source.key
      content  = source.value
    }
  }
}
resource "oci_objectstorage_object" "model" {
  count        = local.enabled ? 1 : 0
  namespace    = var.publication.namespace
  bucket       = var.publication.bucket_name
  object       = local.object_name
  source       = archive_file.model[0].output_sha256 != "" ? archive_file.model[0].output_path : null
  content_type = "application/zip"
  metadata = {
    "template-sha256"   = local.template_hash, "zip-sha256" = archive_file.model[0].output_sha256,
    "model-spec-sha256" = sha256(jsonencode(var.model_spec)), "platform-binding-sha256" = sha256(jsonencode(var.platform_binding))
  }
}
resource "oci_objectstorage_object" "launch" {
  count        = local.enabled ? 1 : 0
  namespace    = var.publication.namespace
  bucket       = var.publication.bucket_name
  object       = local.launch_name
  source       = archive_file.model[0].output_sha256 != "" ? archive_file.model[0].output_path : null
  content_type = "application/zip"
  metadata     = oci_objectstorage_object.model[0].metadata
}
resource "oci_objectstorage_preauthrequest" "model" {
  count        = local.enabled ? 1 : 0
  namespace    = var.publication.namespace
  bucket       = var.publication.bucket_name
  object_name  = oci_objectstorage_object.launch[0].object
  name         = local.filename
  access_type  = "ObjectRead"
  time_expires = timeadd(local.published_at, "${var.publication.par_lifetime_hours}h")
}
locals {
  par_url = try(replace(oci_objectstorage_preauthrequest.model[0].full_path, "/^https://[^./]+\\.objectstorage\\.([a-z0-9-]+)\\.oci\\.customer-oci\\.com//", "https://objectstorage.$1.oraclecloud.com/"), null)
}
output "deployment" {
  precondition {
    condition     = local.enabled ? try(length(local.par_url) <= 256, false) : true
    error_message = "Generated model package URL exceeds RMS ZipOrigin's 256-character limit. Download the ZIP and upload it instead."
  }
  value = local.enabled ? {
    kind                 = "llm_deployment", region = var.platform_binding.region, artifact_region = var.publication.region,
    published_at         = local.published_at, expires_at = oci_objectstorage_preauthrequest.model[0].time_expires,
    object_name          = local.object_name, launch_object_name = local.launch_name, download_url = local.par_url,
    launch_url           = "https://cloud.oracle.com/resourcemanager/stacks/create?region=${urlencode(var.platform_binding.region)}&zipUrl=${urlencode(local.par_url)}",
    zip_sha256           = archive_file.model[0].output_sha256, platform_binding_sha256 = sha256(jsonencode(var.platform_binding)),
    gpu_allocation_bound = try(var.platform_binding.allocation.gpu_pool_id != null, false),
    next_step            = "Create model pipelines, run the trusted platform onboarding pipeline with their exact IDs, then run model preflight. GPU runtime deployment is never started automatically."
  } : null
}
