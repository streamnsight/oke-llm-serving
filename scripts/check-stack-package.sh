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
for required in main.tf variables.tf schema.yaml .terraform.lock.hcl modules; do
  [[ -e "$staging/$required" ]] || { echo "Missing package asset: $required" >&2; exit 1; }
done
for group in "$staging/modules/"*/; do
  case "$(basename "$group")" in discovery|infrastructure|cluster-add-ons|llm-deployment|shared) ;;
    *) echo "Ungrouped module directory: $group" >&2; exit 1;;
  esac
done
for required in modules/cluster-add-ons/platform-bootstrap/scripts/cleanup-repository.sh modules/shared/component-delivery/main.tf modules/shared/component-delivery/scripts/component.sh modules/llm-deployment/model-delivery/main.tf; do
  [[ -e "$staging/$required" ]] || { echo "Missing delivery asset: $required" >&2; exit 1; }
done
if [[ $(jq -r .stack "$staging/package-manifest.json") == discovery ]]; then
  for required in modules/discovery/discovery-report/main.tf modules/discovery/discovery-report/report.html.tftpl modules/discovery/discovery-report/report.js modules/discovery/discovery-report/styles/tokens.css modules/discovery/discovery-report/styles/app-shell.css modules/discovery/discovery-report/styles/report.css modules/discovery/oci-discovery/scripts/discover-oci.sh modules/discovery/accelerator-inventory/data/gpus.json modules/discovery/infrastructure-publisher/main.tf modules/discovery/model-publisher/main.tf modules/llm-deployment/model-target/main.tf modules/llm-deployment/model-project/main.tf modules/infrastructure/gpu-allocation/main.tf modules/cluster-add-ons/platform-bootstrap/main.tf modules/cluster-add-ons/oke-managed-addons/main.tf modules/cluster-add-ons/oke-managed-addons/scripts/ensure-addons.sh; do
    [[ -e "$staging/$required" ]] || { echo "Missing discovery/platform asset: $required" >&2; exit 1; }
  done
fi
[[ ! -d "$staging/modules/llm-deployment/devops-serving" && ! -d "$staging/templates/deployment" ]] || { echo 'Package retains the obsolete combined model/infrastructure deployment.' >&2; exit 1; }
for obsolete in terraform catalogs scripts devops; do
  [[ ! -e "$staging/$obsolete" ]] || { echo "Package contains obsolete root directory: $obsolete" >&2; exit 1; }
done
if find "$staging" \( -name .terraform -o -name node_modules -o -name .git -o -name work -o -name tests -o -name '*.tfstate*' -o -name '*.tfplan' -o -name '*.tfvars' -o -name '*.tfvars.json' \) -print | grep -q .; then
  echo 'Package contains development/private artifacts' >&2; exit 1
fi
jq -e '.working_directory=="." and (.stack=="discovery" or .stack=="infrastructure" or .stack=="llm-deployment") and (.source_commit|test("^[a-f0-9]{40}$"))' "$staging/package-manifest.json" >/dev/null
terraform -chdir="$staging" init -backend=false -input=false -no-color
terraform -chdir="$staging" validate -no-color
if [[ $(jq -r .stack "$staging/package-manifest.json") == discovery ]]; then
  jq -e '.templates==["infrastructure","llm-deployment"]' "$staging/package-manifest.json" >/dev/null
  for template in infrastructure llm-deployment; do
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
