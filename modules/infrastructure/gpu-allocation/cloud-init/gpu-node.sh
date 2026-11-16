#!/bin/bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Follow OKE's custom cloud-init Example 5 without changing its init logic:
# https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengusingcustomcloudinitscripts.htm
# stdout/stderr are retained in the node's cloud-init-output.log.
set -euo pipefail
umask 077
phase='IMDSv2 bootstrap download'
trap 'status=$?; printf "[oke-llm] Node bootstrap failed during %s (exit %s)\n" "$phase" "$status" >&2; exit "$status"' ERR
printf '[oke-llm] %s\n' "$phase"
# OKE publishes its canonical init script base64-encoded in IMDSv2 metadata.
curl --fail --retry 3 --connect-timeout 10 --max-time 120 -H "Authorization: Bearer Oracle" -L0 http://169.254.169.254/opc/v2/instance/metadata/oke_init_script | base64 --decode >/var/run/oke-init.sh
test -s /var/run/oke-init.sh
phase='root filesystem expansion'
printf '[oke-llm] %s\n' "$phase"
bash /usr/libexec/oci-growfs -y
phase='OKE node initialization'
printf '[oke-llm] %s\n' "$phase"
bash /var/run/oke-init.sh
printf '[oke-llm] Node bootstrap completed\n'
