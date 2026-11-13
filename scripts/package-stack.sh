#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Package committed source with module-owned runtime assets.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'Usage: package-stack.sh OUTPUT.zip' >&2; exit 2; }
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
package_stack=${PACKAGE_STACK:-discovery}
case "$package_stack" in discovery|infrastructure|deployment) ;; *) echo 'PACKAGE_STACK must be discovery, infrastructure or deployment' >&2; exit 2;; esac
output=$1
[[ "$output" == /* ]] || output="$PWD/$output"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
git -C "$repo" archive HEAD | tar -x -C "$staging"
# Discovery is the repository root. Child templates remain independent roots.
package="$staging/package"
mkdir -p "$package"
source_root=$staging
if [[ "$package_stack" != discovery ]]; then source_root="$staging/templates/$package_stack"; fi
for file in "$source_root/"*.tf "$source_root/"*.tf.json; do
  if [[ -f "$file" ]]; then cp "$file" "$package/"; fi
done
cp "$source_root/schema.yaml" "$source_root/.terraform.lock.hcl" "$package/"
if [[ -f "$source_root/target.example.json" ]]; then cp "$source_root/target.example.json" "$package/"; fi
cp -R "$staging/modules" "$package/modules"
if [[ "$package_stack" == discovery ]]; then cp -R "$staging/templates" "$package/templates"; fi
for asset in outputs docs; do cp -R "$staging/$asset" "$package/$asset"; done
cp "$staging/README.md" "$staging/LICENSE.txt" "$staging/SECURITY.md" "$package/"
# Only committed source is staged. Remove development tests before relocation.
find "$package" -type d -name tests -prune -exec rm -rf {} +
for file in "$package/"*.tf; do
  sed -e 's|"../../modules/|"./modules/|g' -e 's|${path.module}/../../modules/|${path.module}/modules/|g' "$file" > "$file.relocated"
  mv "$file.relocated" "$file"
done
jq -n --arg selected "$package_stack" --arg commit "$(git -C "$repo" rev-parse HEAD)" '{stack:$selected,source_commit:$commit,working_directory:".",templates:(if $selected=="discovery" then ["infrastructure","deployment"] else [] end)}' > "$package/package-manifest.json"
(cd "$package" && zip -qr "$staging/stack.zip" .)
mkdir -p "$(dirname "$output")"
mv "$staging/stack.zip" "$output"
echo "$output"
