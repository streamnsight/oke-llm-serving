#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# OCI Shell runs GNU tar. Normalize order, timestamps and permissions so the
# same immutable source always yields the same OCIR chart bytes on retries.
delivery_archive() {
  local chart=$1 source=$2 destination=$3
  rm -rf chart-source
  mkdir -p "chart-source/$chart"
  cp -R "$source/." "chart-source/$chart/"
  find chart-source -type d -exec chmod 0755 {} +
  find chart-source -type f -exec chmod 0644 {} +
  tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -C chart-source -cf - "$chart" | gzip -n > "$destination"
}
