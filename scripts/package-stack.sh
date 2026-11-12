#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Package committed source with module-owned runtime assets.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'Usage: package-stack.sh OUTPUT.zip' >&2; exit 2; }
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
package_stack=${PACKAGE_STACK:-discovery}
case "$package_stack" in discovery|deployment) ;; *) echo 'PACKAGE_STACK must be discovery or deployment' >&2; exit 2;; esac
output=$1
[[ "$output" == /* ]] || output="$PWD/$output"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
git -C "$repo" archive HEAD | tar -x -C "$staging"
# Each archive is a standalone Terraform root. Repository paths stay unchanged.
package="$staging/package"
mkdir -p "$package"
cp -R "$staging/terraform/stacks/$package_stack/." "$package/"
cp -R "$staging/terraform/modules" "$package/modules"
for asset in outputs docs; do cp -R "$staging/$asset" "$package/$asset"; done
cp "$staging/README.md" "$staging/LICENSE.txt" "$staging/SECURITY.md" "$package/"
# Only committed source is staged. Remove development tests before relocation.
find "$package" -type d -name tests -prune -exec rm -rf {} +
for file in "$package/"*.tf; do
  sed -e 's|"../../modules/|"./modules/|g' -e 's|${path.module}/../../modules/|${path.module}/modules/|g' "$file" > "$file.relocated"
  mv "$file.relocated" "$file"
done
jq -n --arg selected "$package_stack" --arg commit "$(git -C "$repo" rev-parse HEAD)" '{stack:$selected,source_commit:$commit,working_directory:"."}' > "$package/package-manifest.json"
(cd "$package" && zip -qr "$staging/stack.zip" .)
mkdir -p "$(dirname "$output")"
mv "$staging/stack.zip" "$output"
echo "$output"
