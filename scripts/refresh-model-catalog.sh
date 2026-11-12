#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Packaging/maintainer hook; requires Node and the repository's YAML dev dependency.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
node "$repo/scripts/recipe-model-catalog.mjs" "${1:-$repo}"
