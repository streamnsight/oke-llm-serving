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
  # The store also holds the HTML report, including assessments with no options.
  published_at = terraform_data.publication[0].output
  # Model ZIPs are published alongside infrastructure directly by discovery.
  dependencies = toset(["infrastructure/gpu-allocation", "discovery/accelerator-inventory", "discovery/capacity-assessment", "infrastructure/deployment-target", "infrastructure/oke-node-image", "cluster-add-ons/platform-bootstrap", "shared/component-delivery"])
  module_files = merge([for dependency in local.dependencies : {
    for relative in fileset("${var.modules_dir}/${dependency}", "**") : "modules/${dependency}/${relative}" => file("${var.modules_dir}/${dependency}/${relative}")
    if !startswith(relative, ".") && !startswith(relative, "tests/") && !startswith(relative, "work/") && !startswith(relative, "__pycache__/") && !strcontains(relative, "/__pycache__/") && !startswith(relative, "node_modules/") && !strcontains(relative, "/.") &&
    !can(regex("\\.(tfstate(\\..*)?|tfvars(\\.json)?|tfplan)$", relative))
  }]...)
  template_files = { for relative in setunion(fileset(var.template_dir, "*.tf"), toset(["schema.yaml", ".terraform.lock.hcl"])) : relative => replace(file("${var.template_dir}/${relative}"), "../../modules/", "./modules/") }
  template_hash  = sha256(jsonencode({ template = local.template_files, modules = local.module_files }))
  source_commit  = try(jsondecode(file("${var.modules_dir}/../package-manifest.json")).source_commit, null)
  model_folder   = replace(replace(var.model.repository, "/", "--"), "/[^A-Za-z0-9_.-]/", "-")
  schema         = yamldecode(local.template_files["schema.yaml"])
  header         = "# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.\n# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.\n"
  defaults = { for id, option in var.options : id => {
    availability_domain      = option.availability_domain, gpu_shape = option.gpu_shape, node_count = option.node_count,
    boot_volume_gib          = max(200, ceil(try(coalesce(var.model.checkpoint_download_bytes, 0), 0) * max(1, try(option.replicas_per_node, 1)) * 2 / pow(1024, 3)) + 100),
    skip_gpu_allocation      = var.skip_gpu_allocation,
    enable_lws               = try(option.platform_plan.components.lws.required, option.pipeline_parallel_size > 1, false),
    enable_disaggregated_set = try(option.platform_plan.components.lws.enable_disaggregated_set, false),
    monitoring_enabled       = try(option.platform_plan.monitoring.enabled, true),
    autoscaling_enabled      = try(option.platform_plan.autoscaling.enabled, false),
    rdma_mode                = try(option.platform_plan.topology.rdma_required, option.requires_rdma, false) ? "rdma" : "ethernet"
  } }
  specifications = { for id, option in var.options : id => {
    schema_version  = "1.0", kind = "infrastructure", selection_id = id, region = option.region, model = var.model,
    recommendation  = local.defaults[id], selection = option, publication_time = local.published_at,
    template_sha256 = local.template_hash, source_commit = local.source_commit,
    storage_budget = {
      selected_snapshot_bytes = try(var.model.checkpoint_download_bytes, null), replicas_per_host = max(1, try(option.replicas_per_node, 1)),
      boot_volume_gib         = local.defaults[id].boot_volume_gib,
      basis                   = "Two snapshot copies per packed engine Pod plus 100 GiB for OS/images/working space, minimum 200 GiB. No shared cache or TP-based checkpoint division assumed. Check actual ephemeral allocatable capacity before deployment."
    }
  } }
}
resource "terraform_data" "identity" {
  count = 1
}
resource "terraform_data" "publication" {
  count            = 1
  triggers_replace = uuid()
  input            = timestamp()
}
locals {
  run_id       = substr(replace(terraform_data.publication[0].id, "-", ""), 0, 12)
  filenames    = { for id, option in var.options : id => "infrastructure-${formatdate("YYYYMMDD'T'hhmmss'Z'", local.published_at)}-${local.run_id}-${id}.zip" }
  object_names = { for id, option in var.options : id => "models/${local.model_folder}/${option.region}/${replace(option.gpu_shape, "/[^A-Za-z0-9_.-]/", "-")}/${local.filenames[id]}" }
  # Console copies zipUrl into ZipOrigin (maximum 256 characters). Keep the
  # browsable archive path and use a bounded filename for its launch copy.
  launch_object_names = { for id, option in var.options : id => "rms/${local.run_id}-${substr(sha256(id), 0, 16)}.zip" }
  files = { for id, option in var.options : id => merge(local.template_files, local.module_files, {
    "schema.yaml"                      = "${local.header}${yamlencode(merge(local.schema, { variables = { for key, value in local.schema.variables : key => merge(value, try({ default = local.defaults[id][key] }, {})) } }))}",
    "recommendations_override.tf.json" = jsonencode({ variable = { for key, value in local.defaults[id] : key => { default = value } } }),
    "inputs/infrastructure-spec.json"  = jsonencode(local.specifications[id]),
    "LICENSE.txt"                      = file("${var.modules_dir}/../LICENSE.txt"),
    "bundle-manifest.json"             = jsonencode({ kind = "infrastructure", selection_id = id, expected_region = option.region, published_at = local.published_at, run_id = local.run_id, template_sha256 = local.template_hash, payload_sha256 = sha256(jsonencode(local.specifications[id])), source_commit = local.source_commit })
  }) }
}
data "oci_objectstorage_namespace" "artifacts" {
  count          = 1
  compartment_id = var.tenancy_ocid
}
resource "oci_objectstorage_bucket" "artifacts" {
  count          = 1
  compartment_id = var.compartment_id
  namespace      = data.oci_objectstorage_namespace.artifacts[0].namespace
  name           = "oke-llm-bundles-${substr(sha256(terraform_data.identity[0].id), 0, 16)}"
  access_type    = "NoPublicAccess"
}
# The resource creates ZIPs at Apply, including when Plan and Apply use
# different workers. Every publication has a new manifest/time/run identity.
resource "archive_file" "infrastructure" {
  for_each         = var.options
  type             = "zip"
  output_path      = "${path.root}/.generated/infrastructure-${each.key}.zip"
  output_file_mode = "0644"
  dynamic "source" {
    for_each = local.files[each.key]
    content {
      filename = source.key
      content  = source.value
    }
  }
}
resource "oci_objectstorage_object" "infrastructure" {
  for_each  = var.options
  namespace = data.oci_objectstorage_namespace.artifacts[0].namespace
  bucket    = oci_objectstorage_bucket.artifacts[0].name
  object    = local.object_names[each.key]
  # A computed checksum defers the local-file argument until archive creation.
  source       = archive_file.infrastructure[each.key].output_sha256 != "" ? archive_file.infrastructure[each.key].output_path : null
  content_type = "application/zip"
  metadata = {
    "template-sha256" = local.template_hash, "zip-sha256" = archive_file.infrastructure[each.key].output_sha256,
    "selection-id"    = each.key, "capacity-observed-at" = try(coalesce(each.value.capacity_observed_at, "unknown"), "unknown")
  }
}
resource "oci_objectstorage_preauthrequest" "infrastructure" {
  for_each     = var.options
  namespace    = data.oci_objectstorage_namespace.artifacts[0].namespace
  bucket       = oci_objectstorage_bucket.artifacts[0].name
  object_name  = oci_objectstorage_object.launch[each.key].object
  name         = local.filenames[each.key]
  access_type  = "ObjectRead"
  time_expires = timeadd(local.published_at, "${var.par_lifetime_hours}h")
}
resource "oci_objectstorage_object" "launch" {
  for_each     = var.options
  namespace    = data.oci_objectstorage_namespace.artifacts[0].namespace
  bucket       = oci_objectstorage_bucket.artifacts[0].name
  object       = local.launch_object_names[each.key]
  source       = archive_file.infrastructure[each.key].output_sha256 != "" ? archive_file.infrastructure[each.key].output_path : null
  content_type = "application/zip"
  metadata     = oci_objectstorage_object.infrastructure[each.key].metadata
}
locals {
  # RMS's package importer accepts the documented classic Object Storage URL.
  # Recent SDKs return namespaced customer endpoints instead. Change only that
  # commercial hostname; retain the storage region and complete PAR path.
  rms_par_urls = { for id, par in oci_objectstorage_preauthrequest.infrastructure : id => replace(
    par.full_path,
    "/^https://[^./]+\\.objectstorage\\.([a-z0-9-]+)\\.oci\\.customer-oci\\.com//",
    "https://objectstorage.$1.oraclecloud.com/"
  ) }
}
output "deployment_options" {
  precondition {
    condition     = alltrue([for url in values(local.rms_par_urls) : length(url) <= 256])
    error_message = "RMS copies zipUrl into its ZipOrigin tag, which is limited to 256 characters. A generated package URL exceeds that limit; download the ZIP and upload it directly instead."
  }
  value = { for id, option in var.options : id => {
    kind                 = "infrastructure", region = option.region, artifact_region = var.region, availability_domain = option.availability_domain,
    gpu_shape            = option.gpu_shape, node_count = option.node_count, availability = option.availability,
    replicas             = try(option.replicas, null), replicas_per_node = try(option.replicas_per_node, null), platform_plan = try(option.platform_plan, null),
    capacity_observed_at = try(option.capacity_observed_at, null), configuration_status = try(option.configuration_status, "requires_validation"),
    object_name          = local.object_names[id], launch_object_name = local.launch_object_names[id], published_at = local.published_at, expires_at = oci_objectstorage_preauthrequest.infrastructure[id].time_expires,
    zip_sha256           = archive_file.infrastructure[id].output_sha256, download_url = local.rms_par_urls[id],
    launch_url           = "https://cloud.oracle.com/resourcemanager/stacks/create?region=${urlencode(option.region)}&zipUrl=${urlencode(local.rms_par_urls[id])}",
    skip_gpu_allocation  = var.skip_gpu_allocation,
    remaining_input      = "Select an existing cluster and review Plan. Apply creates platform resources and, unless debug skipping is enabled, GPU hosts."
  } }
}
