#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
target_os=${1:-$(uname -s | tr '[:upper:]' '[:lower:]')}
target_arch=${2:-$(uname -m)}
case "$target_arch" in x86_64) target_arch=amd64;; aarch64) target_arch=arm64;; esac
case "$target_os/$target_arch" in linux/amd64|linux/arm64|darwin/amd64|darwin/arm64) ;; *) echo 'Unsupported SDK binary platform' >&2; exit 2;; esac
export GOPATH=${GOPATH:-$repo/work/go}
export GOCACHE=${GOCACHE:-$repo/work/go-build-cache}
destination="$repo/bin/${target_os}_${target_arch}"
mkdir -p "$destination"
CGO_ENABLED=0 GOOS="$target_os" GOARCH="$target_arch" go -C "$repo/tools/oci-discovery" build -mod=readonly -buildvcs=false -trimpath -ldflags='-s -w' -o "$destination/oci-discovery" .
if command -v sha256sum >/dev/null; then sha256sum "$destination/oci-discovery" | cut -d ' ' -f 1 > "$destination/oci-discovery.sha256"
else shasum -a 256 "$destination/oci-discovery" | cut -d ' ' -f 1 > "$destination/oci-discovery.sha256"; fi
printf '%s\n' "$destination/oci-discovery"
