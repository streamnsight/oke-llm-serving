#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
source runtime/common.sh
model_inputs
model_geometry
model_platform_ready
model_storage
# Recipes may refer to a companion without provisioning it. Refuse that
# incomplete runtime instead of claiming that argv alone creates a KV backend.
if jq -e '(.serving.recipe.companions // [])|length>0' "$model_config" >/dev/null; then
  model_fail 'Recipe declares companion services. This adapter does not provision LMCache MP servers/disaggregated services; select a complete assessed adapter/configuration first'
fi
# Pin every byte of the optional upstream router dependency. The parent chart
# owns only namespaced model/router objects, never its bundled controllers.
mkdir -p chart/charts
curl -fsSL --retry 3 https://vllm-project.github.io/production-stack/vllm-stack-0.1.14.tgz -o chart/charts/vllm-stack-0.1.14.tgz
printf '%s  chart/charts/vllm-stack-0.1.14.tgz\n' 6d03d2f28c34a7a2d05da62d3df44e349d662424e947f240b343a97f24f99c3c | sha256sum -c -
