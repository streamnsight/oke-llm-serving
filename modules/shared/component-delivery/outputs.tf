# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
output "component_pipeline_ids" {
  value = { for key, c in var.components : key => oci_devops_deploy_pipeline.component["${key}/deploy"].id if c.mode != "retire" }
}
output "undeploy_pipeline_ids" {
  value = { for key, c in var.components : key => oci_devops_deploy_pipeline.component["${key}/undeploy"].id if c.mode != "reuse" }
}
output "all_pipeline_ids" {
  value = [for key in sort(keys(local.operations)) : oci_devops_deploy_pipeline.component[key].id]
}
output "chart_repositories" {
  value = { for key, repo in oci_artifacts_container_repository.chart : key => { id = repo.id, name = repo.display_name, url = local.specifications[key].mirror_url } }
}
output "generations" { value = local.generations }
output "owner_names" {
  value = { for key, c in var.components : key => "oke-llm-owner-${substr(sha256("${c.namespace}/${c.release_name}"), 0, 24)}" }
}
output "result_prefixes" {
  value = { for key, c in var.components : key => "${var.name}/components/${key}/${local.generations[key]}" }
}
output "runtime_artifacts" {
  description = "Existing runtime inputs reusable by sibling operation pipelines without duplicate publication."
  value = { for path, artifact in oci_generic_artifacts_content_artifact_by_path.runtime : path => {
    artifact_id = artifact.artifact_id, artifact_path = artifact.artifact_path, version = artifact.version
  } }
}
