# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_providers { http = { source = "hashicorp/http", version = "~> 3.4" } }
}
variable "context_length" { default = 4096 }
module "model_profile" {
  source = "../../../modules/discovery/model-profile"
  model = "Qwen/Qwen3.8-27B"
  context_length = var.context_length
  concurrency = 4
}
module "planner" {
  source = "../../../modules/discovery/deployment-planner"
  profile = module.model_profile.profile
  engines = []
  recipe_api_enabled = true
  serving_resolution = {engine={platform="linux/amd64",image="fixture",id="stable",version="0.34.0",architectures=["Qwen3_5ForConditionalGeneration"],gpu_compute_capabilities=[86,90],multi_node_backend="mp"},recipe={feature_options={},compatible_strategies=["single_node_tp"]}}
  regions = local.regions
}
output "profile" { value = module.model_profile.profile }
output "assessment" { value = module.planner.assessment }

locals { regions = [{inventory={region="ca-montreal-1",availability_domains=[{name="AD-1",shapes=[{shape="BM.GPU.A10.4",gpus=4,gpu_memory_bytes_per_gpu=24000000000,rdma_ports=0,quota_names=["gpu-count"]}]}],limits=[{name="gpu-count",description="GPUs for test instances",scope_type="AD",availability_domain="AD-1",tenancy_limit=64,resource_availability={status="observed",available=64}}]},capacity={region="ca-montreal-1",availability_domains=[{name="AD-1",assessment={observed_at="fixture",shapes=[{shape="BM.GPU.A10.4",available_instances=1,availability_status="AVAILABLE"}]}}]}}] }
module "report" {
  source = "../../../modules/discovery/discovery-report"
  profile = module.model_profile.profile
  assessment = module.planner.assessment
  regions = local.regions
  options = {for option in module.planner.assessment.suggestions : option.id => option}
  publications = {}
  scan = {assessed_regions=["ca-montreal-1"]}
  serving_configuration = {}
}
output "report" {value=module.report.summary}
output "html" {value=module.report.html}
