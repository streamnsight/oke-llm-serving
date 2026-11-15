#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Development-only check of a discovery-generated model package.
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: check-generated-model.sh MODEL.zip' >&2; exit 2; }
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
unzip -tq "$1"
unzip -q "$1" -d "$staging"
for required in main.tf variables.tf schema.yaml .terraform.lock.hcl recommendations_override.tf.json inputs/model-spec.json bundle-manifest.json modules/llm-deployment/model-target/main.tf modules/llm-deployment/model-project/main.tf modules/llm-deployment/model-delivery/main.tf modules/llm-deployment/model-storage/main.tf modules/shared/component-delivery/main.tf modules/shared/inline-command-spec/main.tf; do
  [[ -f "$staging/$required" ]] || { echo "Missing model asset: $required" >&2; exit 1; }
done
[[ ! -e "$staging/inputs/platform-binding.json" ]] || { echo 'Model bundle still depends on an infrastructure Apply output.' >&2; exit 1; }
for excluded in templates modules/infrastructure modules/cluster-add-ons modules/discovery; do
  [[ ! -e "$staging/$excluded" ]] || { echo "Model bundle contains another stage: $excluded" >&2; exit 1; }
done
if find "$staging" \( -name .terraform -o -name node_modules -o -name tests -o -name '*.tfvars*' -o -name '*.tfstate*' \) -print | grep -q .; then
  echo 'Model bundle includes development/private files or tfvars that shadow RMS defaults.' >&2; exit 1
fi
jq -e '.kind=="llm_deployment" and .schema_version=="2.0" and (.expected_region|type)=="string" and (.selection_id|type)=="string"' "$staging/bundle-manifest.json" >/dev/null
jq -e '.selection.availability=="available_at_scan" and .selection.node_count>=1 and (.selection.region|type)=="string"' "$staging/inputs/model-spec.json" >/dev/null
terraform -chdir="$staging" init -backend=false -input=false -no-color
terraform -chdir="$staging" validate -no-color
IFS=. read -r terraform_major terraform_minor _ <<< "$(terraform version -json | jq -r .terraform_version)"
if (( terraform_major > 1 || (terraform_major == 1 && terraform_minor >= 7) )); then
  mkdir "$staging/tests"
  cp "$repo/tests/fixtures/generated-model.hcl" "$staging/tests/generated.tftest.hcl"
  terraform -chdir="$staging" test -no-color
else
  echo 'Mock-provider root tests require Terraform 1.7+; this version validates RMS compatibility only.'
fi
echo "Validated configured model-only package: $1"
