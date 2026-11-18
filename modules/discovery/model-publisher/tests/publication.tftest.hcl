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
  publication  = { namespace = "fixture", bucket_name = "original-discovery-bundles", region = "us-chicago-1", published_at = "2026-11-14T10:00:00Z", par_lifetime_hours = 24 }
  model_spec = {
    schema_version = "1.0", kind = "llm_model", selection_id = "selected", source_commit = "source-commit",
    model          = { repository = "org/model", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", context_length = 8192, concurrency = 8, checkpoint_download_bytes = 107374182400 },
    profile        = { memory = { assumptions = { context_length = 4096, concurrency = 1 } } },
    selection = {
      region               = "eu-frankfurt-1", availability_domain = "AD-1", gpu_shape = "BM.GPU.H100.8", gpus_per_node = 8, availability = "available_at_scan",
      tensor_parallel_size = 4, pipeline_parallel_size = 1, replicas = 2, node_count = 1,
      platform_plan = { monitoring = { enabled = true }, autoscaling = { enabled = false }, components = {
        prometheus = { required = true }, keda = { required = false }, gpu_telemetry = { required = true }
      } },
      serving_configuration = { engine = { image = "vllm/vllm-openai@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }, recipe = { args = ["--reasoning-parser", "qwen3", "--tool-call-parser", "qwen3_coder"], env = { VLLM_USE_RUST_FRONTEND = "1" }, original_evidence = join("", [for i in range(900) : "0123456789"]) } }
    }
  }
}
run "no_model_or_publication_context_creates_no_resources" {
  command = plan
  variables { model_spec = null }
  assert {
    condition     = output.deployment == null && length(archive_file.model) == 0 && length(oci_objectstorage_object.model) == 0 && length(oci_objectstorage_preauthrequest.model) == 0
    error_message = "Missing model evidence disables publication without requiring an infrastructure Apply output."
  }
}
run "plan_never_requires_a_previous_worker_archive" {
  command = plan
  assert {
    condition     = local.files["modules/shared/artifact-repository-cleanup/scripts/cleanup-repository.sh"] == file("${var.modules_dir}/shared/artifact-repository-cleanup/scripts/cleanup-repository.sh")
    error_message = "Generated stacks must include their destroy-time repository cleanup runtime asset."
  }
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
    condition     = jsondecode(local.files["inputs/model-spec.json"]).selection == var.model_spec.selection && length(local.files["inputs/model-spec.json"]) > 8192 && !contains(keys(local.files), "inputs/platform-binding.json") && !contains(keys(local.defaults), "cluster_id") && !contains(keys(local.defaults), "gpu_pool_id") && !contains(keys(local.defaults), "region")
    error_message = "Preserve full selection/recipe evidence in a file; region, cluster and retained GPU pool remain launch-time selections, without any infrastructure Apply output."
  }
  assert {
    condition     = alltrue([for key, value in local.defaults : jsondecode(local.files["recommendations_override.tf.json"]).variable[key].default == value && yamldecode(local.files["schema.yaml"]).variables[key].default == value]) && local.defaults.tensor_parallel_size == 4 && local.defaults.replicas == 2 && local.defaults.context_length == 8192 && !contains(keys(local.files), "terraform.tfvars.json")
    error_message = "Recommend editable geometry/context defaults consistently in both HCL and RMS schema; tfvars must not override user edits."
  }
  assert {
    condition     = local.defaults.monitoring_enabled && !local.defaults.autoscaling_enabled && !contains(keys(local.defaults), "storage_mode") && yamldecode(local.files["schema.yaml"]).variables.storage_mode.default == "direct_hf"
    error_message = "Monitoring/scaling remain editable recommendations; weight delivery defaults belong to the model template, not discovery policy."
  }
  assert {
    condition     = alltrue([for filename in keys(local.files) : !startswith(filename, "templates/") && !startswith(filename, "modules/infrastructure/") && !startswith(filename, "modules/discovery/") && !strcontains(filename, "/tests/")]) && alltrue([for dependency in ["model-target", "model-project", "model-delivery", "model-storage"] : contains(keys(local.files), "modules/llm-deployment/${dependency}/main.tf")])
    error_message = "The model ZIP must contain only runtime dependencies, without recursive publishers or infrastructure resources."
  }
}
run "selected_engine_beats_global_fallback_and_numeric_org_is_a_safe_release" {
  command = plan
  variables {
    model_spec = {
      model                 = { repository = "01-ai/model", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
      selection             = { region = "eu-frankfurt-1", gpu_shape = "BM.GPU.H100.8", node_count = 1, availability = "available_at_scan", tensor_parallel_size = 2, pipeline_parallel_size = 1, replicas = 1, engine = { image = "vllm/vllm-openai@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } },
      serving_configuration = { engine = { image = "vllm/vllm-openai@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" }, recipe = { args = ["--tool-call-parser", "qwen3_coder"] } }
    }
  }
  assert {
    condition     = local.defaults.serving_image == "vllm/vllm-openai@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" && can(regex("^[a-z][a-z0-9-]+$", local.defaults.model_name)) && !contains(keys(local.defaults), "workspace_gib")
    error_message = "The chosen platform image must override global fallback evidence, and valid numeric Hub organizations must still generate a safe model release name."
  }
}
run "missing_publication_context_is_disabled" {
  command = plan
  variables { publication = null }
  assert {
    condition     = output.deployment == null && length(archive_file.model) == 0
    error_message = "Do not create a second publication store when no shared context is provided."
  }
}
run "unconfirmed_capacity_never_produces_a_deployable_model_zip" {
  command = plan
  variables {
    model_spec = { selection_id = "excluded", model = { repository = "org/model" }, selection = { region = "eu-frankfurt-1", gpu_shape = "BM.GPU.H100.8", node_count = 1, availability = "unconfirmed" } }
  }
  expect_failures = [terraform_data.publication]
}
run "model_options_have_distinct_archive_paths_and_shared_expiry" {
  command = apply
  variables {
    model_spec = {
      selection_id = "other-ad", model = { repository = "org/model", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, profile = {},
      selection = {
        region               = "eu-frankfurt-1", availability_domain = "AD-2", gpu_shape = "BM.GPU.H100.8", gpus_per_node = 8, node_count = 1, availability = "available_at_scan",
        tensor_parallel_size = 4, pipeline_parallel_size = 1, replicas = 2,
        engine               = { image = "vllm/vllm-openai@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
      }
    }
  }
  assert {
    condition     = output.deployment.selection_id == "other-ad" && output.deployment.published_at == var.publication.published_at && output.deployment.expires_at == "2026-11-15T10:00:00Z" && archive_file.model[0].output_path == "${path.root}/.generated/model-${substr(sha256(jsonencode(var.model_spec)), 0, 20)}.zip" && length(output.deployment.launch_object_name) == 37
    error_message = "Same-model options need independent archive paths, filename run IDs and the common discovery PAR expiry."
  }
}

run "cache_profile_defaults_remain_editable_in_rms" {
  command = plan
  variables {
    model_spec = {
      schema_version = "1.0", kind = "llm_model", selection_id = "cache-profile",
      model          = { repository = "another-org/attention-model", revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
      selection = {
        region = "eu-frankfurt-1", gpu_shape = "BM.GPU.H100.8", node_count = 1, availability = "available_at_scan", tensor_parallel_size = 1, pipeline_parallel_size = 1, replicas = 1,
        serving_configuration = {
          engine             = { image = "vllm/vllm-openai@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" },
          deployment_profile = { lmcache = { mode = "mp", cpu_memory_gb = 12, chunk_size = 128 }, routing = { mode = "prefixaware" } }
        }
      }
    }
  }
  assert {
    condition     = local.defaults.lmcache_mode == "mp" && local.defaults.lmcache_cpu_memory_gb == 12 && local.defaults.lmcache_chunk_size == 128 && local.defaults.routing_mode == "prefixaware" && yamldecode(local.files["schema.yaml"]).variables.lmcache_mode.default == "mp" && jsondecode(local.files["recommendations_override.tf.json"]).variable.lmcache_mode.default == "mp" && contains(keys(local.files), "modules/llm-deployment/model-delivery/chart/files/lmcache-launch.sh")
    error_message = "Recipe cache recommendations and readable runtime assets must survive publication, without model-specific branches or hidden tfvars."
  }
}
run "explicit_KV_routing_publishes_a_paired_controller_configuration" {
  command = apply
  variables { model_spec = merge(var.model_spec, { model = merge(var.model_spec.model, { routing_mode = "kvaware" }) }) }
  assert {
    condition     = local.defaults.replicas == 2 && local.defaults.router_enabled && local.defaults.routing_mode == "kvaware" && local.defaults.lmcache_mode == "inprocess" && alltrue([for key in ["replicas", "router_enabled", "routing_mode", "lmcache_mode"] : jsondecode(local.files["recommendations_override.tf.json"]).variable[key].default == local.defaults[key] && yamldecode(local.files["schema.yaml"]).variables[key].default == local.defaults[key]])
    error_message = "KV-aware routing must enable its router and in-process LMCache controller in both editable Terraform and RMS defaults."
  }
  assert {
    condition     = jsondecode(local.files["inputs/model-spec.json"]).selection == var.model_spec.selection
    error_message = "The explicit routing policy must not rewrite the assessed upstream recipe."
  }
}
