#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Local post-processing only. Does not invoke Terraform or contact cloud services.
set -euo pipefail
[[ $# -eq 3 ]] || { echo 'Usage: select-deployment.sh discovery.json CANDIDATE_ID target.json > deployment.tfvars.json' >&2; exit 2; }
jq -en --slurpfile discovery "$1" --arg id "$2" --slurpfile target "$3" '
  $discovery[0] as $d | $target[0] as $t |
  [($d.assessment.candidates[]?, $d.assessment.sizing_options[]?) | select(.id==$id)] as $matches |
  (if ($matches|length)!=1 then error("Select exactly one reported candidate") else $matches[0] end) as $c |
  if all(["tenancy_ocid","compartment_id","cluster_id","subnet_id","gpu_image_id","cpu_image_id","cpu_subnet_id","devops_subnet_id","name"][]; . as $key | ($t[$key]|type)=="string" and ($t[$key]|length)>0) then . else error("Target is missing deployment fields") end |
  ($d.serving_configuration // null) as $resolution |
  (($t.expert_configuration // false)==true) as $expert |
  ($c.engine // $resolution.engine // {}) as $base_engine |
  (if $expert then $base_engine + {image:($t.engine_image // $base_engine.image),version:($t.engine_version // $base_engine.version),platform:($t.engine_platform // $base_engine.platform),runtime_validation:"not_run"} + (if $t.engine_image!=null then {image_source_association:"expert_override_not_verified"} else {} end) else $base_engine end) as $engine |
  if $expert and $t.engine_image!=null and (($t.engine_version // "")=="" or ($t.engine_platform // "")=="") then error("Expert image override requires engine_version and engine_platform") else . end |
  if ($c.configuration_status=="undetermined_requires_expert" or $c.configuration_status=="requires_recipe_review") and ($expert|not) then error("Selected option has no determined serving configuration; supply expert_configuration and explicit settings") else . end |
  if $c.configuration_status=="undetermined_requires_expert" and $expert then
    if all(["tensor_parallel_size","pipeline_parallel_size","node_count","replicas"][]; . as $key|($t[$key]|type)=="number" and $t[$key]>0) and
      ($t.node_count==$t.pipeline_parallel_size*$t.replicas) and
      ($t.tensor_parallel_size<=$c.gpus_per_node) and
      ($t.expert_rank_memory_gib|type)=="number" and $t.expert_rank_memory_gib>0
    then . else error("Expert option requires explicit TP, PP, replicas, node_count=PP*replicas and expert_rank_memory_gib") end
  else . end |
  if $resolution!=null and $resolution.status!="resolved_requires_validation" and ($expert|not) then error("Unresolved recipe/image evidence requires expert configuration") else . end |
  if ($d.profile.model.resolved_revision|test("^[a-fA-F0-9]{40}$")) and (($engine.image // "")|test("@sha256:[a-f0-9]{64}$")) then . else error("Model and image must be immutable") end |
  ($c + (if $expert then ($t|{node_count,tensor_parallel_size,pipeline_parallel_size,replicas}|with_entries(select(.value!=null))) else {} end)) as $selected |
  $t + {
    region:$c.region,availability_domain:$c.availability_domain,gpu_shape:$c.gpu_shape,node_count:$selected.node_count,
    requires_rdma:($t.requires_rdma // $c.requires_rdma // false),tensor_parallel_size:$selected.tensor_parallel_size,pipeline_parallel_size:$selected.pipeline_parallel_size,replicas:$selected.replicas,
    model:$d.profile.model.repository,model_revision:$d.profile.model.resolved_revision,engine_image:$engine.image,engine_version:$engine.version,
    serving_configuration:(if $resolution!=null then $resolution+{engine:$engine} else null end),expert_configuration:$expert,
    engine_args:($t.engine_args // $resolution.recipe.args // []),engine_env:($t.engine_env // $resolution.recipe.env // {}),
    expert_rank_memory_gib:($t.expert_rank_memory_gib // null),
    context_length:$d.profile.memory.assumptions.context_length,concurrency:$d.profile.memory.assumptions.concurrency,kv_dtype:$d.profile.memory.assumptions.kv_dtype,runtime_gib:($d.profile.memory.assumptions.runtime_allowance_gib // 2),margin:($d.profile.memory.assumptions.safety_margin_fraction // 0.2),
    observation_id:("allocation-"+$d.observation_id+"-"+$c.id),assessment_id:$c.id,
    boot_volume_gib:([$t.boot_volume_gib // 200, (($d.profile.weights.tensor_data_bytes*1.3/1073741824 + 100)|ceil)]|max)
  } | del(.engine_platform)'
