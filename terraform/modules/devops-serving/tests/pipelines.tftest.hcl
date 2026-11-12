# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {}
variables {
  tenancy_ocid   = "root"
  compartment_id = "target"
  subnet_id      = "runner-subnet"
  name           = "fixture"
  config         = { benchmark_requests = 50, benchmark_input_tokens = 1024, benchmark_output_tokens = 128 }
}
run "benchmark_has_numeric_pipeline_parameters" {
  command = plan
  assert {
    condition     = toset([for item in oci_devops_deploy_pipeline.task["benchmark"].deploy_pipeline_parameters[0].items : item.name]) == toset(["BENCHMARK_REQUESTS", "BENCHMARK_INPUT_TOKENS", "BENCHMARK_OUTPUT_TOKENS"]) && length(oci_devops_deploy_pipeline.task["deploy"].deploy_pipeline_parameters) == 0
    error_message = "Expose tuning on the benchmark run, not routine RMS configuration or deploy/validate pipelines."
  }
  assert {
    condition     = oci_devops_deploy_artifact.command["benchmark"].argument_substitution_mode == "NONE"
    error_message = "Keep frozen recipe/shell placeholders literal; load numeric overrides as JSON instead of substituting script source."
  }
}
