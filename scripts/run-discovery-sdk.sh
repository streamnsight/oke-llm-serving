#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
platform_os=$(uname -s | tr '[:upper:]' '[:lower:]')
platform_arch=$(uname -m)
case "$platform_arch" in x86_64) platform_arch=amd64;; aarch64) platform_arch=arm64;; esac
binary="$repo/bin/${platform_os}_${platform_arch}/oci-discovery"
[[ -x "$binary" && -f "$binary.sha256" ]] || { echo 'Missing discovery SDK binary. Run make build-discovery-sdk locally or use the RMS ZIP.' >&2; exit 2; }
if command -v sha256sum >/dev/null; then actual=$(sha256sum "$binary" | cut -d ' ' -f 1)
else actual=$(shasum -a 256 "$binary" | cut -d ' ' -f 1); fi
[[ "$actual" == "$(cat "$binary.sha256")" ]] || { echo 'Discovery SDK binary checksum mismatch' >&2; exit 2; }
exec "$binary"
