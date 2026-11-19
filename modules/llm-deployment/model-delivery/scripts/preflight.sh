#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
source runtime/common.sh
model_inputs
# Preserve recipe intent: this chart's explicit MP implementation must never
# silently replace a Ray or disaggregated execution requirement.
jq -e '
  (.model.selection.platform_plan.topology // {}) as $t |
  (($t.backend // "mp") | .=="mp" or .=="native_mp" or .=="none") and
  (($t.strategy // "single_node_tp") | .=="single_node_tp" or .=="multi_node_tp_pp" or .=="native_pd") and
  ((.serving.recipe.args // []) as $args | all(range(0;$args|length); . as $i |
    if ($args[$i]=="--distributed-executor-backend") then $args[$i+1]=="mp"
    elif ($args[$i]|startswith("--distributed-executor-backend=")) then $args[$i]=="--distributed-executor-backend=mp"
    else true end))
' "$model_config" >/dev/null || model_fail 'This model chart implements native multiprocessing only; selected Ray, P/D or other execution strategies require their own complete adapter'
model_geometry
model_platform_ready
model_storage
# Recipes may refer to a companion without provisioning it. Refuse that
# incomplete runtime instead of claiming that argv alone creates a KV backend.
jq -e '
  (.serving.recipe.companions // []) as $companions |
  ($companions|length)==0 or
  (.lmcache.mode=="mp" and all($companions[]; type=="object" and .adapter=="lmcache_mp" and (keys==["adapter"])))
' "$model_config" >/dev/null || model_fail 'Unprovisioned recipe companion: only the explicit lmcache_mp adapter is implemented; select a complete compatible model profile'
# Pin every byte of the optional upstream router dependency. The parent chart
# owns only namespaced model/router objects, never its bundled controllers.
mkdir -p chart/charts
curl -fsSL --retry 3 https://vllm-project.github.io/production-stack/vllm-stack-0.1.14.tgz -o chart/charts/vllm-stack-0.1.14.tgz
printf '%s  chart/charts/vllm-stack-0.1.14.tgz\n' 6d03d2f28c34a7a2d05da62d3df44e349d662424e947f240b343a97f24f99c3c | sha256sum -c -
