#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
[[ $# -eq 2 ]] || { echo 'Usage: generate-model-schema.sh catalog.json schema.yaml' >&2; exit 2; }
jq -e '.schema_version=="1.0" and (.models|type)=="array" and ([.models[].id]|length== (unique|length)) and all(.models[]; (.id|test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) and (.sha==null or (.sha // ""|test("^[a-f0-9]{40}$"))))' "$1" >/dev/null
schema_temp=$(mktemp -d)
trap 'rm -rf "$schema_temp"' EXIT
printf '      - custom\n' > "$schema_temp/choices"
jq -r '.models|sort_by([(.id|ascii_downcase),.id])|.[].id|"      - "+.' "$1" >> "$schema_temp/choices"
awk -v choices="$schema_temp/choices" '
 /# BEGIN GENERATED MODEL CHOICES/{print; while((getline line < choices)>0)print line; inside=1; starts++; next}
 /# END GENERATED MODEL CHOICES/{inside=0; ends++; print; next}
 !inside{print}
 END{if(starts!=1 || ends!=1)exit 2}
' "$2" > "$schema_temp/schema.yaml"
cp "$schema_temp/schema.yaml" "$2"
