<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# GPU worker root filesystem and model workspace

Success means the existing model can schedule using the GPU host's already allocated boot volume, future GPU workers grow their filesystem before OKE initialization, and oversized local model workspaces fail before Helm. GPU instance allocation, pool size and hardware identity remain unchanged.

## Phase 1 — diagnose

- [x] Verify namespace ownership and the actual target cluster before reading its nodes/pods.
- [x] Confirm the Pod requests 104 GiB of ephemeral storage; its GPU node has only 26.49 GiB allocatable.
- [x] Confirm the node pool already specifies a 204 GiB boot volume while the running Oracle Linux 9.8 root filesystem exposes only 31,608,274,944 bytes.
- [x] Check the checkpoint: 55,563,006,776 bytes (51.75 GiB); the calculated default is 68 GiB, so reducing the request to fit the current filesystem would be incorrect.
- [x] Verify Oracle's documented grow-root-before-OKE cloud-init procedure and in-place existing-worker procedure.

## Phase 2 — implement and prepare

- [x] Add a readable module-owned cloud-init script: fetch standard OKE initialization through IMDSv2, run oci-growfs, then run standard OKE initialization. Keep only API transport encoding in node metadata.
- [x] Add a direct-HF workspace feasibility ceiling using the GPU-node observations already collected by preflight; account for packed replicas and multi-host layouts, without claiming free capacity.
- [x] Prepare an explicit inspection/dry-run procedure for the exact existing node and its already allocated boot volume. Review its concrete output before applying host changes.
- [x] Preserve the infrastructure stack inputs and upload the bootstrap source fix. No infrastructure Apply, GPU pool update or node cycling was performed; future-worker metadata still requires a reviewed infrastructure Apply.

## Phase 3 — verify

- [x] Run focused shell/chart/Terraform regressions and validate the actual generated ZIPs with Terraform 1.5.7.
- [x] Repair the existing root filesystem in place after approval, refresh kubelet capacity, and verify node identity/GPU allocation remain unchanged.
- [x] Confirm the model schedules and actual health validation succeeds. Its Lease was already released, so no forced recovery or blind Lease deletion was used.
- [x] Record the current RMS outcome, commit and rebuild the usable packages.

Oracle procedures: [existing-worker root partition](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengextendingrootpartitionmanually.htm), [cloud-init Example 5](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengusingcustomcloudinitscripts.htm), [oci-growfs utility](https://docs.oracle.com/en-us/iaas/oracle-linux/oci/oci-utilities-reference.htm).

The earlier Helm install succeeded, but readiness failed while the model Pod was unschedulable because root-filesystem capacity was too small. Delayed logs confirmed the readiness script had run. After this repair and the later image/frontend/revision fixes, the Pod became Ready and automatic model validation succeeded. Benchmarks remain manual.

## Read-only existing-node inspection

The guarded inspection Pod completed successfully on node `10.0.10.19`. Host IMDSv2 confirmed the exact instance; the single backing disk is 219,043,332,096 bytes (204 GiB), partition `/dev/sda3` is 47,782,559,744 bytes, and root XFS/LVM is about 29.5 GiB. Oracle `oci-growfs -n` reported a successful partition-expansion dry run and answered No before expansion. No filesystem growth or kubelet restart was requested. The temporary inspection Pod is removed after collecting its output.

The user explicitly approved existing-host `--apply`. It expands the existing filesystem and briefly restarts kubelet; it does not change a volume size, reboot/recycle a node, or allocate GPUs.

## Approved in-place repair result

The existing filesystem grew to 200,613,560,320 bytes; kubelet now reports 180,552,203,990 bytes (168.2 GiB) allocatable ephemeral storage. Node UID, instance OCID and OS boot ID are unchanged, Node Ready is True and all four GPUs remain allocatable. The existing model Pod scheduled onto the GPU node. No volume-size update, GPU allocation, OS reboot or node recycling occurred. Both temporary maintenance Pods are deleted after collecting their logs.

The first maintenance renderer omitted host IPC: the one repair-owned LVM cookie waited in the private Pod IPC namespace while host udev had already settled. After confirming the exact waiter/cookie, active root LV and settled host queue, the operator completed only that one cookie; the original grow operation completed successfully. Future renderers enter host IPC/UTS, and the host script rejects a mismatched IPC namespace before any growfs call.

Validation: 24 allocation Terraform tests, 6 executable bootstrap tests, 4 guarded maintenance tests and 32 model runtime tests passed. The combined JavaScript/shell run passed 154 tests with 3 optional skips; configured model ZIP tests and Terraform 1.5.7 archive checks passed. The subsequent fully qualified image/frontend/revision fixes also passed live: model health and independent validation succeeded, and a separate text request returned OK. Those startup issues were separate from root-disk capacity.
