#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Development-only verification; never invoked inside a Terraform configuration.
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: check-generated-infrastructure.sh GENERATED_TEST.zip' >&2; exit 2; }
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
unzip -tq "$1"
unzip -q "$1" -d "$staging"
for required in main.tf schema.yaml .terraform.lock.hcl recommendations_override.tf.json inputs/infrastructure-spec.json bundle-manifest.json; do
  [[ -f "$staging/$required" ]] || { echo "Missing rendered asset: $required" >&2; exit 1; }
done
[[ ! -d "$staging/templates/infrastructure" && ! -d "$staging/modules/discovery/infrastructure-publisher" ]]
[[ ! -d "$staging/templates" && ! -d "$staging/modules/llm-deployment" && ! -d "$staging/modules/discovery/model-publisher" ]]
if find "$staging" \( -name .terraform -o -name tests -o -name '*.tfstate*' -o -name '*.tfvars*' \) -print | grep -q .; then
  echo 'Rendered ZIP contains development/private files or tfvars that shadow Console edits.' >&2; exit 1
fi
mkdir "$staging/tests"
cp "$repo/tests/fixtures/generated-infrastructure.hcl" "$staging/tests/generated.tftest.hcl"
terraform -chdir="$staging" init -backend=false -input=false -no-color
terraform -chdir="$staging" validate -no-color
terraform -chdir="$staging" test -no-color

# Verify the real archive resource survives a saved Plan transferred to a fresh
# working directory. This fixture has no OCI provider or cloud resources.
mkdir "$staging/plan-worker" "$staging/apply-worker"
cat > "$staging/plan-worker/main.tf" <<'HCL'
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
terraform {
  required_providers { archive = { source = "hashicorp/archive", version = "~> 2.8" } }
}
resource "archive_file" "worker_check" {
  type        = "zip"
  output_path = "${path.root}/stack.zip"
  source {
    filename = "worker-check.txt"
    content  = "saved Plan; fresh Apply worker"
  }
}
HCL
terraform -chdir="$staging/plan-worker" init -backend=false -input=false -no-color
terraform -chdir="$staging/plan-worker" plan -input=false -no-color -out=worker.tfplan
[[ ! -f "$staging/plan-worker/stack.zip" ]]
cp "$staging/plan-worker/main.tf" "$staging/plan-worker/.terraform.lock.hcl" "$staging/plan-worker/worker.tfplan" "$staging/apply-worker/"
terraform -chdir="$staging/apply-worker" init -backend=false -input=false -no-color
terraform -chdir="$staging/apply-worker" apply -input=false -no-color worker.tfplan
[[ $(unzip -p "$staging/apply-worker/stack.zip" worker-check.txt) == 'saved Plan; fresh Apply worker' ]]
echo 'Verified archive creation in a fresh Apply directory from a saved Plan.'
