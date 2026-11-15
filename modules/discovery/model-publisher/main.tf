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
  dependencies = toset(["llm-deployment/model-target", "llm-deployment/model-project", "llm-deployment/model-delivery", "llm-deployment/model-storage", "shared/component-delivery"])
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
  region         = try(coalesce(local.selected.region, "unselected"), "unselected")
  shape          = try(coalesce(local.selected.gpu_shape, "unselected"), "unselected")
  model_folder   = replace(replace(local.repository, "/", "--"), "/[^A-Za-z0-9_.-]/", "-")
  model_name     = "m-${substr(replace(lower(local.repository), "/[^a-z0-9-]/", "-"), 0, 13)}-${substr(sha256(local.repository), 0, 6)}"
  snapshot_bytes = try(coalesce(try(var.model_spec.model.checkpoint_download_bytes, null), try(var.model_spec.profile.weights.checkpoint_download_bytes, null)), null)
  recommendation = {
    model_name           = local.model_name,
    model_id             = local.repository, model_revision = try(coalesce(try(var.model_spec.model.revision, null), try(var.model_spec.profile.model.resolved_revision, null)), ""),
    serving_image        = try(coalesce(try(local.selected.serving_configuration.engine.image, null), try(local.selected.engine.image, null), try(var.model_spec.serving_configuration.engine.image, null)), ""),
    tensor_parallel_size = try(local.selected.tensor_parallel_size, 1), pipeline_parallel_size = try(local.selected.pipeline_parallel_size, 1),
    hosts_per_replica    = try(local.selected.hosts_per_replica, local.selected.pipeline_parallel_size, 1),
    gpus_per_pod         = try(local.selected.gpus_per_pod, local.selected.tensor_parallel_size, 1), replicas = try(local.selected.replicas, 1),
    context_length       = try(coalesce(try(var.model_spec.model.context_length, null), try(var.model_spec.profile.memory.assumptions.context_length, null)), 4096),
    concurrency          = try(coalesce(try(var.model_spec.model.concurrency, null), try(var.model_spec.profile.memory.assumptions.concurrency, null)), 1)
    monitoring_enabled   = try(local.selected.platform_plan.monitoring.enabled, true)
    workspace_gib        = local.snapshot_bytes == null ? 64 : max(20, ceil(local.snapshot_bytes * 2 / pow(1024, 3))),
    router_enabled       = try(local.selected.replicas > 1, false) || try(local.selected.platform_plan.autoscaling.enabled, false),
    autoscaling_enabled  = try(local.selected.platform_plan.autoscaling.enabled, false),
    min_replicas         = try(local.selected.requested_minimum_replicas, local.selected.replicas, 1),
    max_replicas         = try(local.selected.replicas, 1)
  }
  defaults      = { for key, value in local.recommendation : key => value if contains(keys(local.schema.variables), key) && (key != "workspace_gib" || local.snapshot_bytes != null) }
  template_hash = sha256(jsonencode({ template = local.template_files, modules = local.module_files }))
  header        = "# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.\n# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.\n"
  published_at  = try(var.publication.published_at, "")
  run_id        = local.enabled ? substr(replace(terraform_data.publication[0].id, "-", ""), 0, 12) : ""
  filename      = local.enabled ? "model-${formatdate("YYYYMMDD'T'hhmmss'Z'", local.published_at)}-${local.run_id}-${substr(sha256(jsonencode(var.model_spec)), 0, 12)}.zip" : ""
  object_name   = "models/${local.model_folder}/${local.region}/${replace(local.shape, "/[^A-Za-z0-9_.-]/", "-")}/${local.filename}"
  launch_name   = "rms/${local.run_id}-${substr(sha256("model/${jsonencode(var.model_spec)}"), 0, 16)}.zip"
  files = local.enabled ? merge(local.template_files, local.module_files, {
    "schema.yaml"                      = "${local.header}${yamlencode(merge(local.schema, { variables = { for key, value in local.schema.variables : key => merge(value, try({ default = local.defaults[key] }, {})) } }))}",
    "recommendations_override.tf.json" = jsonencode({ variable = { for key, value in local.defaults : key => { default = value } } }),
    "inputs/model-spec.json"           = jsonencode(var.model_spec),
    "LICENSE.txt"                      = file("${var.modules_dir}/../LICENSE.txt"),
    "bundle-manifest.json" = jsonencode({
      kind           = "llm_deployment", schema_version = "2.0", expected_region = local.region, published_at = local.published_at,
      selection_id   = try(var.model_spec.selection_id, null), run_id = local.run_id, template_sha256 = local.template_hash,
      payload_sha256 = sha256(jsonencode(var.model_spec)), source_commit = try(var.model_spec.source_commit, null),
      prerequisites  = "Select an existing OKE cluster. A matching managed GPU pool is inferred or resolved later; this model stack creates its own DevOps project and never allocates GPUs."
    })
  }) : {}
}
resource "terraform_data" "publication" {
  count            = local.enabled ? 1 : 0
  triggers_replace = uuid()
  input            = local.published_at
  lifecycle {
    precondition {
      condition     = try(local.selected.availability == "available_at_scan" && local.selected.node_count >= 1 && floor(local.selected.node_count) == local.selected.node_count && length(local.selected.region) > 0 && length(local.selected.gpu_shape) > 0, false)
      error_message = "Publish only a capacity/headroom-confirmed selection with region, shape and a positive whole-host count."
    }
  }
}
# Resource rather than data source: Plan and Apply may run on different RMS workers.
resource "archive_file" "model" {
  count = local.enabled ? 1 : 0
  type  = "zip"
  # Distinct options for the same model may publish in parallel.
  output_path      = "${path.root}/.generated/model-${substr(sha256(jsonencode(var.model_spec)), 0, 20)}.zip"
  output_file_mode = "0644"
  dynamic "source" {
    for_each = local.files
    content {
      filename = source.key
      content  = source.value
    }
  }
  depends_on = [terraform_data.publication]
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
    "model-spec-sha256" = sha256(jsonencode(var.model_spec)), "selection-id" = try(var.model_spec.selection_id, "selected")
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
    kind         = "llm_deployment", selection_id = try(var.model_spec.selection_id, null), region = local.region, artifact_region = var.publication.region,
    published_at = local.published_at, expires_at = oci_objectstorage_preauthrequest.model[0].time_expires,
    object_name  = local.object_name, launch_object_name = local.launch_name, download_url = local.par_url,
    launch_url   = "https://cloud.oracle.com/resourcemanager/stacks/create?region=${urlencode(local.region)}&zipUrl=${urlencode(local.par_url)}",
    zip_sha256   = archive_file.model[0].output_sha256, gpu_allocation_bound = false,
    next_step    = "Select an existing OKE cluster; pool and network metadata are inferred. Create the independent model DevOps project, onboard exact pipeline IDs, then run model preflight. No runtime starts automatically."
  } : null
}
