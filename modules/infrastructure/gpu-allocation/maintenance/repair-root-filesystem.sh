#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Run on the exact validated host. Inspection is the default; no package installation.
set -euo pipefail
fail() { echo "$*" >&2; exit 2; }
[[ $# -ge 2 && $# -le 3 ]] || fail 'Usage: repair-root-filesystem.sh EXPECTED_INSTANCE_OCID EXPECTED_BOOT_BYTES [--apply]'
expected_instance=$1
expected_boot_bytes=$2
action=${3:-inspect}
[[ $expected_instance =~ ^ocid1\.instance\.[A-Za-z0-9._-]+$ && $expected_boot_bytes =~ ^[1-9][0-9]+$ ]] || fail 'Expected exact instance identity and attached boot-volume size in bytes'
[[ $action == inspect || $action == --apply ]] || fail 'Select inspection or explicit --apply'
[[ $(id -u) == 0 ]] || fail 'Existing root/sudo access is required; this script does not change sudo permissions'
for tool in curl jq findmnt lsblk df systemctl /usr/libexec/oci-growfs; do command -v "$tool" >/dev/null || fail "Required host tool is missing: $tool"; done
actual_instance=$(curl --noproxy '*' -fsS --connect-timeout 3 --max-time 10 -H 'Authorization: Bearer Oracle' http://169.254.169.254/opc/v2/instance/ | jq -er .id)
[[ $actual_instance == "$expected_instance" ]] || fail 'Host IMDSv2 identity differs from the validated OCI/Kubernetes instance'
root_source=$(findmnt -n -o SOURCE /)
root_type=$(findmnt -n -o FSTYPE /)
[[ $root_type == xfs || $root_type == ext4 ]] || fail 'Only the Oracle-supported XFS/ext4 root filesystem is eligible'
geometry=$(lsblk --json --bytes --paths --inverse --output NAME,TYPE,SIZE "$root_source")
jq -e --argjson expected "$expected_boot_bytes" '[..|objects|select(.type?=="disk")|{name,size}]|unique_by(.name)|length==1 and .[0].size>=$expected' <<< "$geometry" >/dev/null || fail 'Root must resolve to exactly one disk at least as large as the actual attached boot volume; inspect device geometry manually'
printf 'Validated instance: %s\nRoot source: %s (%s)\n' "$actual_instance" "$root_source" "$root_type"
printf '%s\n' "$geometry"
df -B1 --output=source,fstype,size,used,avail,target /
for tool in pvs vgs lvs; do if command -v "$tool" >/dev/null; then "$tool" --readonly; fi; done
systemctl is-active kubelet.service
echo 'Oracle growfs preview (answers no to expansion):'
/usr/libexec/oci-growfs -n
[[ $action == --apply ]] || { echo 'Inspection complete; no filesystem growth or kubelet restart requested'; exit 0; }
before=$(df -B1 --output=size / | tail -n 1 | tr -d '[:space:]')
/usr/libexec/oci-growfs -y
after=$(df -B1 --output=size / | tail -n 1 | tr -d '[:space:]')
(( after > before )) || fail 'Root filesystem did not increase; kubelet was not restarted. Review growfs output and actual geometry before further changes'
systemctl restart kubelet.service
systemctl is-active kubelet.service
df -B1 --output=source,fstype,size,used,avail,target /
echo 'Filesystem grew in place and kubelet restarted; verify node ephemeral-storage through the Kubernetes API'
