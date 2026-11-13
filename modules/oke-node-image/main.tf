# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_providers { oci = { source = "oracle/oci", version = "~> 9.12" } }
}
variable "cluster_id" { type = string }
variable "compartment_id" { type = string }
variable "kubernetes_version" { type = string }
variable "shape" { type = string }
variable "architecture" { type = string }
variable "os_version" { type = string }
variable "image_id" {
  type    = string
  default = null
}
data "oci_containerengine_node_pool_option" "target" {
  node_pool_option_id = var.cluster_id
  compartment_id      = var.compartment_id
}
locals {
  override    = try(trimspace(var.image_id) != "", false) ? trimspace(var.image_id) : null
  gpu         = strcontains(var.shape, "GPU")
  all_sources = { for s in data.oci_containerengine_node_pool_option.target.sources : s.image_id => s.source_name }
  sources = { for id, name in local.all_sources : id => name if local.override == null &&
    startswith(name, "Oracle-Linux-${var.os_version}.") &&
    strcontains(name, "-OKE-${trimprefix(var.kubernetes_version, "v")}-") &&
    (strcontains(name, "-GPU-") == local.gpu) &&
    (strcontains(name, "-aarch64-") == (var.architecture == "arm64"))
  }
  ids = local.override == null ? toset(keys(local.sources)) : toset([local.override])
}
data "oci_core_image" "candidate" {
  for_each = local.ids
  image_id = each.key
}
data "oci_core_image_shapes" "candidate" {
  for_each = local.ids
  image_id = each.key
}
locals {
  compatible = { for id, image in data.oci_core_image.candidate : id => image if image.state == "AVAILABLE" && contains(data.oci_containerengine_node_pool_option.target.shapes, var.shape) &&
    contains([for s in data.oci_core_image_shapes.candidate[id].image_shape_compatibilities : s.shape], var.shape) &&
    (!strcontains(image.display_name, "-OKE-") || strcontains(image.display_name, "-OKE-${trimprefix(var.kubernetes_version, "v")}-"))
  }
  newest      = try(reverse(sort([for id, image in local.compatible : "${image.time_created}|${id}"]))[0], null)
  selected_id = try(split("|", local.newest)[1], null)
}
output "image" {
  value = {
    id                     = local.selected_id, name = try(local.compatible[local.selected_id].display_name, null)
    time_created           = try(local.compatible[local.selected_id].time_created, null), shape = var.shape
    kubernetes_version     = var.kubernetes_version, os_version = var.os_version,
    source                 = local.override == null ? "latest_shape_compatible_oke_source" : "explicit_override",
    status                 = local.selected_id == null ? "no_compatible_image" : "shape_compatible",
    oke_source             = contains(keys(local.all_sources), local.selected_id == null ? "" : local.selected_id),
    driver_cuda_validation = local.gpu ? "requires_runtime_validation_with_serving_image" : "not_applicable"
  }
}
