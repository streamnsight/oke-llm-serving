# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
variables {
  profile = {
    model = { repository = "org/uniform", resolved_revision = "0123456789012345678901234567890123456789" }
    architecture = {
      kind      = "dense", text_only = true, causal_generation = true,
      attention = { layout = "uniform_attention", layer_types = ["full_attention"] }
    }
    memory = { status = "estimated", assumptions = { context_length = 4096, concurrency = 1 } }
  }
  assessment = { recommended_selection_id = "shared" }
  regions    = []
  scan       = { assessed_regions = ["test-region"] }
  serving_configuration = {
    engine = { framework = "vllm" }
    recipe = { args = [], env = {}, companions = [] }
  }
  options = { shared = {
    region                     = "test-region", availability_domain = "AD-1", gpu_shape = "GPU.4",
    gpus_per_node              = 4, node_count = 1, replicas = 2, replicas_per_node = 2,
    requested_minimum_replicas = 1, tensor_parallel_size = 2, pipeline_parallel_size = 1,
    available_instances        = 2, entitled_instances = 2, availability = "available_at_scan"
  } }
  publications = { shared = {
    launch_url   = "https://cloud.oracle.com/resourcemanager/stacks/create?region=test-region&zipUrl=https%3A%2F%2Fstorage.example%2Fp%2Ftoken%2Finfra.zip",
    download_url = "https://storage.example/p/token/infra.zip"
  } }
  model_publications = { shared = {
    launch_url   = "https://cloud.oracle.com/resourcemanager/stacks/create?region=test-region&zipUrl=https%3A%2F%2Fstorage.example%2Fp%2Ftoken%2Fmodel.zip",
    download_url = "https://storage.example/p/token/model.zip"
  } }
}

run "layout_tabs_reuse_archives_with_distinct_scalar_presets" {
  command = plan
  assert {
    condition = (
      output.summary.option_count == 1 && output.summary.published_option_count == 1 &&
      length(output.summary.options) == 1 &&
      length(output.summary.serving_layouts.aggregated.options) == 1 &&
      length(output.summary.serving_layouts.disaggregated.options) == 1 &&
      output.summary.serving_layouts.aggregated.options.shared.links.launch_url == var.publications.shared.launch_url &&
      output.summary.serving_layouts.disaggregated.options.shared.links.download_url == var.publications.shared.download_url &&
      output.summary.serving_layouts.disaggregated.options.shared.links.model_deployment.download_url == var.model_publications.shared.download_url
    )
    error_message = "Both layout tabs must share the existing infrastructure/model archives; no mode-specific publication is needed."
  }
  assert {
    condition = (
      output.summary.serving_layouts.disaggregated.options.shared.allocation.required_hosts == 1 &&
      output.summary.serving_layouts.disaggregated.options.shared.allocation.allocated_gpus == 4 &&
      output.summary.serving_layouts.disaggregated.options.shared.prefill_replicas == 1 &&
      output.summary.serving_layouts.disaggregated.options.shared.decode_replicas == 1 &&
      output.summary.serving_layouts.disaggregated.options.shared.launch_variables.model.serving_mode == "disaggregated" &&
      output.summary.serving_layouts.disaggregated.options.shared.launch_variables.model.replicas == 1 &&
      output.summary.serving_layouts.disaggregated.options.shared.launch_variables.model.lmcache_mode == "disabled" &&
      !output.summary.serving_layouts.disaggregated.options.shared.launch_variables.model.autoscaling_enabled
    )
    error_message = "P/D needs both full-weight role groups and native fixed-replica settings, not the combined option's two decode replicas."
  }
  assert {
    condition = (
      output.summary.serving_layouts.disaggregated.options.shared.links.launch_url == "${var.publications.shared.launch_url}&zipUrlVariables=${urlencode(jsonencode({ node_count = 1 }))}" &&
      startswith(output.summary.serving_layouts.disaggregated.options.shared.links.model_deployment.launch_url, "${var.model_publications.shared.launch_url}&zipUrlVariables=") &&
      strcontains(output.summary.serving_layouts.disaggregated.options.shared.links.model_deployment.launch_url, urlencode("\"serving_mode\":\"disaggregated\"")) &&
      output.summary.serving_layouts.disaggregated.options.shared.recommendation == null &&
      output.summary.serving_layouts.disaggregated.recommended_option_id == "shared"
    )
    error_message = "Use documented URL-encoded scalar quick-create values without changing zipUrl, and do not reuse combined replica-growth metrics for P/D."
  }
}

run "extra_pd_host_is_quantity_checked_and_prefilled_without_another_zip" {
  command = plan
  variables {
    options = { shared = {
      region                     = "test-region", availability_domain = "AD-1", gpu_shape = "GPU.4",
      gpus_per_node              = 4, node_count = 1, replicas = 1, replicas_per_node = 1,
      requested_minimum_replicas = 1, tensor_parallel_size = 4, pipeline_parallel_size = 1,
      available_instances        = 2, entitled_instances = 2, availability = "available_at_scan"
    } }
  }
  assert {
    condition = (
      output.summary.options.shared.allocation.required_hosts == 1 &&
      output.summary.serving_layouts.disaggregated.options.shared.allocation.required_hosts == 2 &&
      output.summary.serving_layouts.disaggregated.options.shared.allocation.allocated_gpus == 8 &&
      output.summary.serving_layouts.disaggregated.options.shared.links.launch_url == "${var.publications.shared.launch_url}&zipUrlVariables=${urlencode(jsonencode({ node_count = 2 }))}" &&
      output.summary.published_option_count == 1
    )
    error_message = "TP4 needs two four-GPU hosts for 1P/1D; the shared infrastructure ZIP must receive the real two-host preset."
  }
}

run "missing_pd_headroom_keeps_combined_option_without_a_pd_launch" {
  command = plan
  variables {
    options = { shared = {
      region                     = "test-region", availability_domain = "AD-1", gpu_shape = "GPU.4",
      gpus_per_node              = 4, node_count = 1, replicas = 1, replicas_per_node = 1,
      requested_minimum_replicas = 1, tensor_parallel_size = 4, pipeline_parallel_size = 1,
      available_instances        = 2, entitled_instances = 1, availability = "available_at_scan"
    } }
  }
  assert {
    condition = (
      length(output.summary.serving_layouts.aggregated.options) == 1 &&
      length(output.summary.serving_layouts.disaggregated.options) == 0 &&
      length(output.summary.serving_layouts.disaggregated.unavailable_options.shared.reasons) > 0
    )
    error_message = "One confirmed combined host does not establish entitlement for the two-host P/D alternative."
  }
}

run "unpublished_report_does_not_invent_pd_launch_links" {
  command = plan
  variables {
    publications       = {}
    model_publications = {}
  }
  assert {
    condition = (
      output.summary.serving_layouts.disaggregated.options.shared.links.launch_url == null &&
      output.summary.serving_layouts.disaggregated.options.shared.links.model_deployment.launch_url == null
    )
    error_message = "An eligible layout without publication must not expose a fabricated create-stack URL."
  }
}
