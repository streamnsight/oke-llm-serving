# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Real archive provider; OCI publication APIs are mocked.
mock_provider "oci" {
  mock_resource "oci_objectstorage_preauthrequest" {
    defaults = { full_path = "https://fixture.objectstorage.us-chicago-1.oci.customer-oci.com/p/short-token/n/fixture/b/bundles/o/rms/model.zip" }
  }
}
variables {
  template_dir = "../../../templates/llm-deployment"
  modules_dir  = "../.."
  publication  = { namespace = "fixture", bucket_name = "original-discovery-bundles", region = "us-chicago-1", par_lifetime_hours = 24 }
  platform_binding = {
    schema_version               = "1.0", platform_name = "platform", generation = "platform-generation", region = "eu-frankfurt-1", gpu_shape = "BM.GPU.H100.8",
    project_id                   = "existing-project", deploy_environment_id = "existing-environment", script_repository_id = "existing-scripts", result_repository_id = "existing-results",
    compartment_id               = "workload-compartment", cluster_id = "cluster", cluster_compartment_id = "cluster-compartment", kubernetes_version = "v1.34.1",
    runner_subnet_id             = "runner-subnet", runner_nsg_ids = [], gpu_selector = "oke-llm/allocation=platform",
    allocation                   = { gpu_pool_id = null, allocation_identity = null, compute_cluster_id = null }, gpu_count_per_host = 8, node_count = 1, gpu_allocation_enabled = false,
    transport                    = { requires_rdma = false, rdma_resource_name = null, mode = "ethernet" },
    monitoring_enabled           = false, autoscaling_enabled = false, required_components = [], components = {}, component_generations = {},
    model_onboarding_pipeline_id = "trusted-onboarding-pipeline", model_storage = { mode = "direct_huggingface" }
  }
  model_spec = {
    schema_version = "1.0", kind = "llm_model", selection_id = "selected", source_commit = "source-commit",
    model          = { repository = "org/model", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", context_length = 8192, concurrency = 8, checkpoint_download_bytes = 107374182400 },
    profile        = { memory = { assumptions = { context_length = 4096, concurrency = 1 } } },
    selection = {
      tensor_parallel_size  = 4, pipeline_parallel_size = 1, replicas = 2, node_count = 1,
      serving_configuration = { engine = { image = "vllm/vllm-openai@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }, recipe = { args = ["--reasoning-parser", "qwen3", "--tool-call-parser", "qwen3_coder"], env = { VLLM_USE_RUST_FRONTEND = "1" }, original_evidence = join("", [for i in range(900) : "0123456789"]) } }
    }
  }
}
run "no_model_or_publication_context_creates_no_resources" {
  command = plan
  variables { model_spec = null }
  assert {
    condition     = output.deployment == null && length(archive_file.model) == 0 && length(oci_objectstorage_object.model) == 0 && length(oci_objectstorage_preauthrequest.model) == 0
    error_message = "A manually created infrastructure stack without a frozen selection must not invent a model bundle or bucket."
  }
}
run "plan_never_requires_a_previous_worker_archive" {
  command = plan
  assert {
    condition     = local.enabled && length(local.files) > 4 && strcontains(local.files["main.tf"], "./modules/llm-deployment/model-delivery") && contains(keys(local.files), "variables.tf") && local.files["variables.tf"] == file("${var.template_dir}/variables.tf") && contains(keys(local.files), "modules/llm-deployment/model-delivery/chart/templates/workload.yaml")
    error_message = "The model template must be rooted at the ZIP root with file-relative module paths."
  }
}
run "apply_creates_real_root_archive_and_reuses_original_bucket_region" {
  command = apply
  assert {
    condition     = fileexists(archive_file.model[0].output_path) && archive_file.model[0].output_size > 1000 && oci_objectstorage_object.model[0].bucket == "original-discovery-bundles" && output.deployment.artifact_region == "us-chicago-1" && output.deployment.region == "eu-frankfurt-1"
    error_message = "Create the ZIP at Apply and publish into the existing discovery bucket, even when its region differs from the GPU cluster."
  }
  assert {
    condition     = output.deployment.download_url == "https://objectstorage.us-chicago-1.oraclecloud.com/p/short-token/n/fixture/b/bundles/o/rms/model.zip" && strcontains(output.deployment.launch_url, "region=eu-frankfurt-1&zipUrl=") && oci_objectstorage_preauthrequest.model[0].object_name == oci_objectstorage_object.launch[0].object && oci_objectstorage_preauthrequest.model[0].access_type == "ObjectRead"
    error_message = "Use the verified classic PAR endpoint, exact short launch object and deployment region in the Console URL."
  }
  assert {
    condition     = startswith(output.deployment.object_name, "models/org--model/eu-frankfurt-1/BM.GPU.H100.8/model-") && length(split("/", output.deployment.object_name)) == 5 && output.deployment.expires_at == timeadd(output.deployment.published_at, "24h") && !output.deployment.gpu_allocation_bound
    error_message = "Keep run IDs in filenames and permit explicitly unallocated debug bindings without claiming GPU readiness."
  }
  assert {
    condition     = jsondecode(local.files["inputs/model-spec.json"]).selection.serving_configuration.recipe == var.model_spec.selection.serving_configuration.recipe && length(local.files["inputs/model-spec.json"]) > 8192 && jsondecode(local.files["inputs/platform-binding.json"]).project_id == "existing-project" && jsondecode(local.files["inputs/platform-binding.json"]).allocation.gpu_pool_id == null
    error_message = "Preserve exact recipe argv/env/provenance and platform binding in files, not giant RMS variables."
  }
  assert {
    condition     = alltrue([for key, value in local.defaults : jsondecode(local.files["recommendations_override.tf.json"]).variable[key].default == value && yamldecode(local.files["schema.yaml"]).variables[key].default == value]) && local.defaults.tensor_parallel_size == 4 && local.defaults.replicas == 2 && local.defaults.context_length == 8192 && !contains(keys(local.files), "terraform.tfvars.json")
    error_message = "Recommend editable geometry/context defaults consistently in both HCL and RMS schema; tfvars must not override user edits."
  }
  assert {
    condition     = alltrue([for filename in keys(local.files) : !startswith(filename, "templates/") && !startswith(filename, "modules/infrastructure/") && !startswith(filename, "modules/discovery/") && !strcontains(filename, "/tests/")])
    error_message = "The model ZIP must contain only runtime dependencies, without recursive publishers or infrastructure resources."
  }
}
run "selected_engine_beats_global_fallback_and_numeric_org_is_a_safe_release" {
  command = plan
  variables {
    model_spec = {
      model                 = { repository = "01-ai/model", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
      selection             = { tensor_parallel_size = 2, pipeline_parallel_size = 1, replicas = 1, engine = { image = "vllm/vllm-openai@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } },
      serving_configuration = { engine = { image = "vllm/vllm-openai@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" }, recipe = { args = ["--tool-call-parser", "qwen3_coder"] } }
    }
  }
  assert {
    condition     = local.defaults.serving_image == "vllm/vllm-openai@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" && can(regex("^[a-z][a-z0-9-]+$", local.defaults.model_name)) && length(local.defaults.namespace) <= 63 && !contains(keys(local.defaults), "workspace_gib")
    error_message = "The chosen platform image must override global fallback evidence, and valid numeric Hub organizations must still generate a safe model release name."
  }
}
