#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Package a committed source tree. Optional catalog refresh runs only in the staging tree.
set -euo pipefail
[[ $# -ge 1 && $# -le 2 ]] || { echo 'Usage: package-stack.sh OUTPUT.zip [--refresh-catalog]' >&2; exit 2; }
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output=$1
[[ "$output" == /* ]] || output="$PWD/$output"
[[ ${2:-} == '' || ${2:-} == --refresh-catalog ]] || exit 2
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
git -C "$repo" archive HEAD | tar -x -C "$staging"
if [[ ${2:-} == --refresh-catalog ]]; then bash "$staging/scripts/refresh-model-catalog.sh"; fi
bash "$staging/scripts/generate-model-schema.sh" "$staging/catalogs/models.json" "$staging/terraform/stacks/discovery/schema.yaml"
jq -n --arg commit "$(git -C "$repo" rev-parse HEAD)" --arg catalog "$(shasum -a 256 "$staging/catalogs/models.json" | cut -d ' ' -f 1)" '{source_commit:$commit,model_catalog_sha256:$catalog,working_directories:["terraform/stacks/discovery","terraform/stacks/deployment"]}' > "$staging/package-manifest.json"
# Tracked repository source only; private state/work files never enter the archive.
rm -rf "$staging/work" "$staging/devops/tests"
find "$staging/terraform" -type d -name tests -prune -exec rm -rf {} +
(cd "$staging" && zip -qr "$staging/stack.zip" terraform catalogs devops scripts outputs docs README.md package-manifest.json)
mkdir -p "$(dirname "$output")"
mv "$staging/stack.zip" "$output"
echo "$output"
