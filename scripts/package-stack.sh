#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Package a committed source tree. Optional catalog refresh runs only in the staging tree.
set -euo pipefail
[[ $# -ge 1 && $# -le 2 ]] || { echo 'Usage: package-stack.sh OUTPUT.zip [--refresh-catalog]' >&2; exit 2; }
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
package_stack=${PACKAGE_STACK:-all}
case "$package_stack" in all|discovery|deployment) ;; *) echo 'PACKAGE_STACK must be all, discovery or deployment' >&2; exit 2;; esac
output=$1
[[ "$output" == /* ]] || output="$PWD/$output"
[[ ${2:-} == '' || ${2:-} == --refresh-catalog ]] || exit 2
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
git -C "$repo" archive HEAD | tar -x -C "$staging"
if [[ ${2:-} == --refresh-catalog ]]; then bash "$repo/scripts/refresh-model-catalog.sh" "$staging"; fi
bash "$staging/scripts/validate-model-catalog.sh" "$staging/catalogs/models.json"
if [[ "$package_stack" != all ]]; then
  for stack in discovery deployment; do
    [[ "$stack" == "$package_stack" ]] || rm -rf "$staging/terraform/stacks/$stack"
  done
fi
jq -n --arg selected "$package_stack" --arg commit "$(git -C "$repo" rev-parse HEAD)" --arg catalog "$(shasum -a 256 "$staging/catalogs/models.json" | cut -d ' ' -f 1)" '{source_commit:$commit,model_catalog_sha256:$catalog,working_directories:(if $selected=="all" then ["terraform/stacks/discovery","terraform/stacks/deployment"] else ["terraform/stacks/"+$selected] end)}' > "$staging/package-manifest.json"
if [[ "$package_stack" != deployment ]]; then
  GOPATH="${GOPATH:-$repo/work/go}" GOCACHE="${GOCACHE:-$repo/work/go-build-cache}" bash "$staging/scripts/build-discovery-sdk.sh" linux amd64
  jq --arg binary "$(cat "$staging/bin/linux_amd64/oci-discovery.sha256")" '. + {discovery_binary_sha256:$binary,discovery_binary_platform:"linux_amd64"}' "$staging/package-manifest.json" > "$staging/manifest.tmp"
  mv "$staging/manifest.tmp" "$staging/package-manifest.json"
fi
# Tracked repository source only; private state/work files never enter the archive.
rm -rf "$staging/work" "$staging/devops/tests"
find "$staging/terraform" -type d -name tests -prune -exec rm -rf {} +
find "$staging/tools" -name "*_test.go" -delete
(cd "$staging" && zip -qr "$staging/stack.zip" terraform catalogs devops scripts outputs docs tools README.md LICENSE.txt SECURITY.md package-manifest.json)
if [[ -d "$staging/bin" ]]; then (cd "$staging" && zip -qr "$staging/stack.zip" bin); fi
mkdir -p "$(dirname "$output")"
mv "$staging/stack.zip" "$output"
echo "$output"
