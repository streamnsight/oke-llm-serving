#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Package a committed source tree. Optional catalog refresh runs only in the staging tree.
set -euo pipefail
[[ $# -ge 1 && $# -le 2 ]] || { echo 'Usage: package-stack.sh OUTPUT.zip [--refresh-catalog]' >&2; exit 2; }
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
package_stack=${PACKAGE_STACK:-discovery}
case "$package_stack" in discovery|deployment) ;; *) echo 'PACKAGE_STACK must be discovery or deployment' >&2; exit 2;; esac
output=$1
[[ "$output" == /* ]] || output="$PWD/$output"
[[ ${2:-} == '' || ${2:-} == --refresh-catalog ]] || exit 2
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
git -C "$repo" archive HEAD | tar -x -C "$staging"
if [[ ${2:-} == --refresh-catalog ]]; then bash "$repo/scripts/refresh-model-catalog.sh" "$staging"; fi
bash "$staging/scripts/validate-model-catalog.sh" "$staging/catalogs/models.json"
# Each archive is a standalone Terraform root. Repository paths stay unchanged.
package="$staging/package"
mkdir -p "$package"
cp -R "$staging/terraform/stacks/$package_stack/." "$package/"
cp -R "$staging/terraform/modules" "$package/modules"
for asset in catalogs devops scripts outputs docs; do cp -R "$staging/$asset" "$package/$asset"; done
cp "$staging/README.md" "$staging/LICENSE.txt" "$staging/SECURITY.md" "$package/"
# Only committed source is staged. Remove development tests before relocation.
find "$package" -type d -name tests -prune -exec rm -rf {} +
for file in "$package/"*.tf; do
  sed -e 's|"../../modules/|"./modules/|g' -e 's|${path.module}/../../../|${path.module}/|g' "$file" > "$file.relocated"
  mv "$file.relocated" "$file"
done
while IFS= read -r -d '' file; do
  sed 's|${path.module}/../../../|${path.module}/../../|g' "$file" > "$file.relocated"
  mv "$file.relocated" "$file"
done < <(find "$package/modules" -type f -name '*.tf' -print0)
jq -n --arg selected "$package_stack" --arg commit "$(git -C "$repo" rev-parse HEAD)" --arg catalog "$(shasum -a 256 "$package/catalogs/models.json" | cut -d ' ' -f 1)" '{stack:$selected,source_commit:$commit,model_catalog_sha256:$catalog,working_directory:"."}' > "$package/package-manifest.json"
(cd "$package" && zip -qr "$staging/stack.zip" .)
mkdir -p "$(dirname "$output")"
mv "$staging/stack.zip" "$output"
echo "$output"
