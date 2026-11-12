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
for required in main.tf variables.tf schema.yaml .terraform.lock.hcl modules modules/oci-discovery/scripts/discover-oci.sh modules/oci-discovery/scripts/lib/oci-discovery.jq modules/accelerator-inventory/data/gpus.json modules/devops-serving/data/components.json modules/devops-serving/scripts/run.sh modules/devops-serving/scripts/render.jq modules/devops-serving/scripts/benchmark.sh modules/devops-serving/scripts/node-capabilities.jq; do
  [[ -e "$staging/$required" ]] || { echo "Missing package asset: $required" >&2; exit 1; }
done
for obsolete in terraform catalogs scripts devops; do
  [[ ! -e "$staging/$obsolete" ]] || { echo "Package contains obsolete root directory: $obsolete" >&2; exit 1; }
done
if find "$staging" \( -name .terraform -o -name node_modules -o -name .git -o -name work -o -name tests -o -name '*.tfstate*' -o -name '*.tfplan' -o -name '*.tfvars' -o -name '*.tfvars.json' \) -print | grep -q .; then
  echo 'Package contains development/private artifacts' >&2; exit 1
fi
jq -e '.working_directory=="." and (.stack=="discovery" or .stack=="deployment") and (.source_commit|test("^[a-f0-9]{40}$"))' "$staging/package-manifest.json" >/dev/null
terraform -chdir="$staging" init -backend=false -input=false -no-color
terraform -chdir="$staging" validate -no-color
echo "Validated root-level package: $archive"
