#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Provider mocks still execute destroy provisioners: put a strict fake CLI first.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PATH="$repo/tests/fixtures/oci-cli:$PATH"
exec terraform -chdir="${1:-$PWD}" test -no-color
