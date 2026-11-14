# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# OCI is mocked; the archive provider really renders the configured child ZIP.
mock_provider "oci" {
  mock_data "oci_objectstorage_namespace" { defaults = { namespace = "fixture" } }
  mock_resource "oci_objectstorage_preauthrequest" {
    defaults = { full_path = "https://objectstorage.us-ashburn-1.oraclecloud.com/p/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/n/fixture12345/b/oke-llm-bundles-0123456789abcdef/o/rms/0123456789ab-0123456789abcdef.zip" }
  }
}
mock_provider "oci" {
  alias = "customer"
  mock_data "oci_objectstorage_namespace" { defaults = { namespace = "fixture" } }
  mock_resource "oci_objectstorage_preauthrequest" {
    defaults = { full_path = "https://fixture.objectstorage.us-chicago-1.oci.customer-oci.com/p/fake%2Ftoken/n/fixture/b/artifacts/o/folder/stack.zip" }
  }
}
mock_provider "oci" {
  alias = "other_realm"
  mock_data "oci_objectstorage_namespace" { defaults = { namespace = "fixture" } }
  mock_resource "oci_objectstorage_preauthrequest" {
    defaults = { full_path = "https://objectstorage.us-langley-1.oraclegovcloud.com/p/fake/n/fixture/b/artifacts/o/stack.zip" }
  }
}
variables {
  tenancy_ocid   = "root"
  compartment_id = "artifacts"
  region         = "us-ashburn-1"
  model          = { repository = "org/model", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", checkpoint_download_bytes = 107374182400 }
  template_dir   = "../../../templates/infrastructure"
  modules_dir    = "../.."
  options = { selected = {
    region       = "us-phoenix-1", availability_domain = "AD-1", gpu_shape = "BM.GPU.A10.4", node_count = 1,
    availability = "available_at_scan", capacity_observed_at = "2026-11-12T18:00:00Z", configuration_status = "suggested_untested", expert_evidence = join("", [for i in range(900) : "0123456789"])
  } }
}
run "plan_does_not_require_a_generated_archive" {
  command = plan
  variables {
    options = { plan_only = { region = "us-phoenix-1", availability_domain = "AD-1", gpu_shape = "BM.GPU.A10.4", node_count = 1, availability = "available_at_scan" } }
  }
  assert {
    condition     = !fileexists("${path.root}/.generated/infrastructure-plan_only.zip")
    error_message = "ZIP generation must happen at Apply, not in the Plan worker."
  }
}
run "apply_renders_zip_and_creates_scoped_links" {
  command = apply
  assert {
    condition     = fileexists(archive_file.infrastructure["selected"].output_path) && archive_file.infrastructure["selected"].output_size > 10000
    error_message = "The real archive provider must create a nonempty child stack at Apply."
  }
  assert {
    condition     = oci_objectstorage_bucket.artifacts[0].access_type == "NoPublicAccess" && oci_objectstorage_preauthrequest.infrastructure["selected"].access_type == "ObjectRead" && oci_objectstorage_preauthrequest.infrastructure["selected"].object_name == oci_objectstorage_object.launch["selected"].object
    error_message = "PARs must read one specific object in a private bucket."
  }
  assert {
    condition     = oci_objectstorage_object.launch["selected"].source == oci_objectstorage_object.infrastructure["selected"].source && oci_objectstorage_object.launch["selected"].metadata["zip-sha256"] == archive_file.infrastructure["selected"].output_sha256 && startswith(output.deployment_options.selected.launch_object_name, "rms/") && length(output.deployment_options.selected.launch_object_name) == 37 && length(output.deployment_options.selected.download_url) <= 256
    error_message = "The short launch copy must contain the identical ZIP, with a package URL fitting the Console origin tag."
  }
  assert {
    condition     = startswith(output.deployment_options["selected"].object_name, "models/org--model/us-phoenix-1/BM.GPU.A10.4/infrastructure-") && length(split("/", output.deployment_options["selected"].object_name)) == 5 && endswith(output.deployment_options["selected"].object_name, "-selected.zip") && output.deployment_options["selected"].expires_at == timeadd(local.published_at, "24h") && strcontains(output.deployment_options["selected"].launch_url, "region=us-phoenix-1&zipUrl=https%3A%2F%2F")
    error_message = "Use fixed folders, filename-only run identity, a bounded PAR lifetime and an encoded region-specific Console link."
  }
  assert {
    condition     = jsondecode(local.files["selected"]["recommendations_override.tf.json"]).variable.boot_volume_gib.default == 300 && yamldecode(local.files["selected"]["schema.yaml"]).variables.node_count.default == 1 && !contains(keys(local.files["selected"]), "terraform.tfvars.json") && !contains(keys(jsondecode(local.files["selected"]["recommendations_override.tf.json"]).variable), "region") && length(local.files["selected"]["inputs/infrastructure-spec.json"]) > 8192
    error_message = "Keep recommendations editable, size disk from checkpoint bytes and preserve the actual RMS region input."
  }
  assert {
    condition     = alltrue([for name in keys(local.files["selected"]) : !startswith(name, "templates/") && !startswith(name, "modules/discovery/infrastructure-publisher/") && !strcontains(name, "/.terraform/") && !strcontains(name, "/tests/")])
    error_message = "Child ZIPs must exclude parents, publisher, tests, provider caches and private state."
  }
}
run "long_model_archive_path_does_not_lengthen_the_launch_url" {
  command = apply
  variables {
    model   = { repository = "organization/a-model-with-a-long-name-and-quantization-revision-for-a-realistic-archive-path", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", checkpoint_download_bytes = 1000 }
    options = { long_model = { region = "eu-frankfurt-1", availability_domain = "AD-2", gpu_shape = "BM.GPU4.8", node_count = 1, availability = "available_at_scan" } }
  }
  assert {
    condition     = length("${split("/o/", local.rms_par_urls.long_model)[0]}/o/${local.object_names.long_model}") > 256 && length(output.deployment_options.long_model.download_url) <= 256 && length(output.deployment_options.long_model.launch_object_name) == 37
    error_message = "Real-length PAR tokens plus descriptive paths reproduce the old failure; the short launch path must avoid it regardless of model name."
  }
}
run "debug_default_is_carried_into_both_editable_defaults" {
  command = apply
  variables {
    skip_gpu_allocation = true
    options             = { debug = { region = "us-phoenix-1", availability_domain = "AD-1", gpu_shape = "BM.GPU.A10.4", node_count = 1, availability = "available_at_scan" } }
  }
  assert {
    condition     = jsondecode(local.files.debug["recommendations_override.tf.json"]).variable.skip_gpu_allocation.default && yamldecode(local.files.debug["schema.yaml"]).variables.skip_gpu_allocation.default && output.deployment_options.debug.skip_gpu_allocation
    error_message = "Debug discovery must produce infrastructure ZIPs that skip GPUs without disabling the platform."
  }
}
run "customer_endpoint_uses_the_classic_storage_host_for_rms" {
  command   = apply
  providers = { oci = oci.customer }
  variables {
    region  = "us-chicago-1"
    options = { customer = { region = "us-phoenix-1", availability_domain = "AD-1", gpu_shape = "BM.GPU.A10.4", node_count = 1, availability = "available_at_scan" } }
  }
  assert {
    condition     = output.deployment_options.customer.download_url == "https://objectstorage.us-chicago-1.oraclecloud.com/p/fake%2Ftoken/n/fixture/b/artifacts/o/folder/stack.zip" && strcontains(output.deployment_options.customer.launch_url, "region=us-phoenix-1&zipUrl=https%3A%2F%2Fobjectstorage.us-chicago-1.oraclecloud.com%2Fp%2Ffake%252Ftoken")
    error_message = "Normalize only the SDK customer hostname, preserving the PAR path, escaping, storage region and target region."
  }
}
run "existing_classic_and_noncommercial_hosts_are_unchanged" {
  command   = apply
  providers = { oci = oci.other_realm }
  variables {
    options = { other_realm = { region = "us-phoenix-1", availability_domain = "AD-1", gpu_shape = "BM.GPU.A10.4", node_count = 1, availability = "available_at_scan" } }
  }
  assert {
    condition     = output.deployment_options.other_realm.download_url == "https://objectstorage.us-langley-1.oraclegovcloud.com/p/fake/n/fixture/b/artifacts/o/stack.zip"
    error_message = "Do not rewrite existing classic or other-realm service endpoints."
  }
}
run "empty_options_create_no_storage" {
  command = plan
  variables { options = {} }
  assert {
    condition     = length(oci_objectstorage_bucket.artifacts) == 0 && length(oci_objectstorage_object.launch) == 0 && length(archive_file.infrastructure) == 0 && length(output.deployment_options) == 0
    error_message = "No confirmed options must create no publication resources."
  }
}
run "reject_unconfirmed_options" {
  command = plan
  variables {
    options = { unavailable = { region = "us-phoenix-1", availability_domain = "AD-1", gpu_shape = "BM.GPU.A10.4", node_count = 1, availability = "unconfirmed" } }
  }
  expect_failures = [var.options]
}
run "reject_package_urls_that_would_create_invalid_origin_tags" {
  command = apply
  variables {
    options = { too_long = { region = "us-phoenix-1", availability_domain = "AD-1", gpu_shape = "BM.GPU.A10.4", node_count = 1, availability = "available_at_scan" } }
  }
  override_resource {
    target = oci_objectstorage_preauthrequest.infrastructure["too_long"]
    values = { full_path = "https://example.com/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.zip" }
  }
  expect_failures = [output.deployment_options]
}
run "component_and_transport_choices_reach_both_editable_defaults" {
  command = plan
  variables {
    options = { configured = {
      region        = "eu-frankfurt-1", availability_domain = "AD-1", gpu_shape = "BM.GPU.H100.8", node_count = 2, availability = "available_at_scan", replicas = 4, replicas_per_node = 2,
      platform_plan = { components = { lws = { required = true, enable_disaggregated_set = true } }, monitoring = { enabled = false }, autoscaling = { enabled = true }, topology = { rdma_required = true } }
    } }
  }
  assert {
    condition     = local.defaults.configured.enable_lws && local.defaults.configured.enable_disaggregated_set && !local.defaults.configured.monitoring_enabled && local.defaults.configured.autoscaling_enabled && local.defaults.configured.rdma_mode == "rdma" && alltrue([for key, value in local.defaults.configured : jsondecode(local.files.configured["recommendations_override.tf.json"]).variable[key].default == value && yamldecode(local.files.configured["schema.yaml"]).variables[key].default == value]) && contains(keys(local.files.configured), "modules/shared/component-delivery/scripts/component.sh") && contains(keys(local.files.configured), "modules/llm-deployment/model-storage/scripts/download.sh")
    error_message = "Generated ZIPs must carry selected component/network defaults in both HCL and RMS and contain every new module dependency."
  }
}
