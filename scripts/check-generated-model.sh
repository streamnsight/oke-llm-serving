#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Development-only check of an infrastructure-bound model package.
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: check-generated-model.sh MODEL.zip' >&2; exit 2; }
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
unzip -tq "$1"
unzip -q "$1" -d "$staging"
for required in main.tf variables.tf schema.yaml .terraform.lock.hcl recommendations_override.tf.json inputs/model-spec.json inputs/platform-binding.json bundle-manifest.json modules/llm-deployment/model-delivery/main.tf modules/shared/component-delivery/main.tf; do
  [[ -f "$staging/$required" ]] || { echo "Missing model asset: $required" >&2; exit 1; }
done
for excluded in templates modules/infrastructure modules/cluster-add-ons modules/discovery; do
  [[ ! -e "$staging/$excluded" ]] || { echo "Model bundle contains another stage: $excluded" >&2; exit 1; }
done
if find "$staging" \( -name .terraform -o -name node_modules -o -name tests -o -name '*.tfvars*' -o -name '*.tfstate*' \) -print | grep -q .; then
  echo 'Model bundle includes development/private files or tfvars that shadow RMS defaults.' >&2; exit 1
fi
jq -e '.kind=="llm_deployment" and (.expected_region|type)=="string"' "$staging/bundle-manifest.json" >/dev/null
terraform -chdir="$staging" init -backend=false -input=false -no-color
terraform -chdir="$staging" validate -no-color
echo "Validated configured model-only package: $1"
