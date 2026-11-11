#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Local post-processing only. Does not invoke Terraform or contact cloud services.
set -euo pipefail
[[ $# -eq 3 ]] || { echo 'Usage: select-deployment.sh discovery.json CANDIDATE_ID target.json > deployment.tfvars.json' >&2; exit 2; }
jq -en --slurpfile discovery "$1" --arg id "$2" --slurpfile target "$3" '
  $discovery[0] as $d | $target[0] as $t |
  [$d.assessment.candidates[] | select(.id==$id)] as $matches |
  (if ($matches|length)!=1 then error("Select exactly one reported candidate") else $matches[0] end) as $c |
  if all(["tenancy_ocid","compartment_id","cluster_id","subnet_id","gpu_image_id","cpu_image_id","cpu_subnet_id","devops_subnet_id","name"][]; . as $key | ($t[$key]|type)=="string" and ($t[$key]|length)>0) then . else error("Target is missing deployment fields") end |
  if ($d.profile.model.resolved_revision|test("^[a-fA-F0-9]{40}$")) and ($c.engine.image|test("@sha256:[a-f0-9]{64}$")) then . else error("Model and image must be immutable") end |
  $t + {
    region:$c.region,availability_domain:$c.availability_domain,gpu_shape:$c.gpu_shape,node_count:$c.node_count,
    requires_rdma:$c.requires_rdma,tensor_parallel_size:$c.tensor_parallel_size,pipeline_parallel_size:$c.pipeline_parallel_size,replicas:$c.replicas,
    model:$d.profile.model.repository,model_revision:$d.profile.model.resolved_revision,engine_image:$c.engine.image,engine_version:$c.engine.version,
    context_length:$d.profile.memory.assumptions.context_length,concurrency:$d.profile.memory.assumptions.concurrency,kv_dtype:$d.profile.memory.assumptions.kv_dtype,runtime_gib:($d.profile.memory.assumptions.runtime_allowance_gib // 2),margin:($d.profile.memory.assumptions.safety_margin_fraction // 0.2),
    observation_id:("allocation-"+$d.observation_id+"-"+$c.id),assessment_id:$c.id,
    boot_volume_gib:([$t.boot_volume_gib // 200, (($d.profile.weights.tensor_data_bytes*1.3/1073741824 + 100)|ceil)]|max)
  }'
