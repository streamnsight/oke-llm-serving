#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Validate the delivered archive, including relocated local module/asset references.
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: check-stack-package.sh STACK.zip' >&2; exit 2; }
archive=$1
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
unzip -tq "$archive"
unzip -q "$archive" -d "$staging"
for required in main.tf variables.tf schema.yaml .terraform.lock.hcl modules modules/discovery/oci-discovery/scripts/discover-oci.sh modules/discovery/oci-discovery/scripts/lib/oci-discovery.jq modules/discovery/accelerator-inventory/data/gpus.json modules/llm-deployment/devops-serving/data/components.json modules/llm-deployment/devops-serving/scripts/run.sh modules/llm-deployment/devops-serving/scripts/render.jq modules/llm-deployment/devops-serving/scripts/benchmark.sh modules/llm-deployment/devops-serving/scripts/node-capabilities.jq modules/llm-deployment/devops-serving/scripts/benchmark-parameters.jq modules/infrastructure/deployment-target/main.tf modules/infrastructure/oke-node-image/main.tf modules/discovery/deployment-handoff/main.tf modules/discovery/control-plane-sizing/main.tf modules/discovery/serving-image-metadata/main.tf; do
  [[ -e "$staging/$required" ]] || { echo "Missing package asset: $required" >&2; exit 1; }
done
for required in modules/cluster-add-ons/platform-bootstrap/main.tf modules/cluster-add-ons/platform-bootstrap/data/components.json modules/cluster-add-ons/platform-bootstrap/scripts/platform.sh modules/shared/component-delivery/main.tf modules/shared/component-delivery/scripts/component.sh modules/shared/component-delivery/scripts/lock.sh modules/shared/component-delivery/scripts/tools.sh modules/llm-deployment/model-storage/main.tf modules/llm-deployment/model-storage/scripts/download.sh modules/cluster-add-ons/platform-bootstrap/scripts/readiness.jq; do
  [[ -e "$staging/$required" ]] || { echo "Missing platform asset: $required" >&2; exit 1; }
done
for obsolete in terraform catalogs scripts devops; do
  [[ ! -e "$staging/$obsolete" ]] || { echo "Package contains obsolete root directory: $obsolete" >&2; exit 1; }
done
[[ -f "$staging/modules/discovery/infrastructure-publisher/main.tf" ]] || { echo 'Missing infrastructure publisher' >&2; exit 1; }
if find "$staging" \( -name .terraform -o -name node_modules -o -name .git -o -name work -o -name tests -o -name '*.tfstate*' -o -name '*.tfplan' -o -name '*.tfvars' -o -name '*.tfvars.json' \) -print | grep -q .; then
  echo 'Package contains development/private artifacts' >&2; exit 1
fi
jq -e '.working_directory=="." and (.stack=="discovery" or .stack=="infrastructure" or .stack=="deployment") and (.source_commit|test("^[a-f0-9]{40}$"))' "$staging/package-manifest.json" >/dev/null
terraform -chdir="$staging" init -backend=false -input=false -no-color
terraform -chdir="$staging" validate -no-color
if [[ $(jq -r .stack "$staging/package-manifest.json") == discovery ]]; then
  jq -e '.templates==["infrastructure","deployment"]' "$staging/package-manifest.json" >/dev/null
  for template in infrastructure deployment; do
    for required in main.tf variables.tf schema.yaml .terraform.lock.hcl; do
      [[ -f "$staging/templates/$template/$required" ]] || { echo "Missing embedded template: $template/$required" >&2; exit 1; }
    done
    terraform -chdir="$staging/templates/$template" init -backend=false -input=false -no-color
    terraform -chdir="$staging/templates/$template" validate -no-color
  done
elif [[ -d "$staging/templates" ]]; then
  echo 'A standalone child package must not embed its parent or sibling templates.' >&2; exit 1
fi
echo "Validated root-level package: $archive"
