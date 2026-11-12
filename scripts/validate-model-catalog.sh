#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'Usage: validate-model-catalog.sh catalog.json' >&2; exit 2; }
jq -e '.schema_version=="1.0" and (.models|type)=="array" and ([.models[].id]|length== (unique|length)) and all(.models[]; (.id|test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) and (.sha==null or (.sha // ""|test("^[a-f0-9]{40}$"))))' "$1" >/dev/null
