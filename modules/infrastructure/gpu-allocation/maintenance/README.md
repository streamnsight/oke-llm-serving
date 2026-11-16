<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->

These are manual, in-place maintenance tools for an existing Oracle Linux GPU node. They do not change a node pool or boot-volume allocation, recycle nodes, install packages, or configure SSH/sudo permissions.

Render a reviewable inspection payload with existing CLI credentials and the intended Kubernetes context:

```bash
bash render-root-repair-command.sh CLUSTER_OCID POOL_OCID NODE_NAME TRUSTED_MODEL_NAMESPACE > inspect-command.json
```

The renderer only reads resources. It checks trusted namespace ownership, the exact node UID/provider identity/allocation, OCI pool membership and shape, and the actual attached boot volume's size. A larger pool setting alone is insufficient. The default native Run Command payload requires an already running agent and existing noninteractive sudo permission; rendering does not prove that remote execution or sudo will work.

For a temporary Kubernetes alternative, append `--pod` to render a node-pinned, privileged, short-lived Pod. Its pinned Oracle Linux image starts the host's own loader and `nsenter` binary, entering the host mount/PID/network/root namespaces before running the same guarded script. No service-account token or GPU request is used. The Pod's `/host` bind is read-only; entering the host mount namespace provides the host view required by Oracle's filesystem tools. Creating this privileged Pod is a separate explicit action. Review its full plaintext command before submitting it and delete only that exact maintenance Pod after collecting its logs.

Both inspection forms verify the host IMDSv2 instance identity, supported filesystem and physical root disk. They print root/LVM/disk geometry and run `oci-growfs -n`, which answers no to expansion. They do not run filesystem growth or restart kubelet.

After reviewing the preview, append `--apply` to render a separate repair payload. It refuses active non-DaemonSet workloads assigned to the node. Submitting that reviewed payload runs `oci-growfs -y`, requires an actual increase in root filesystem size, then restarts kubelet. No node reboot or replacement is involved. If the filesystem is already expanded or does not grow, it stops before restarting kubelet; inspect the geometry separately. Afterwards verify node readiness, increased `ephemeral-storage`, and model scheduling before retrying model deployment.

Oracle documents the [in-place OKE root-partition procedure](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengextendingrootpartitionmanually.htm), [`oci-growfs` behavior](https://docs.oracle.com/en-us/iaas/oracle-linux/oci/oci-utilities-reference.htm), and [Run Command prerequisites](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/runningcommands.htm). No IAM widening, automatic draining, force deletion, or node recycling is performed by these tools.

Local verification uses strict host/OCI/Kubernetes stubs:

```bash
node --test tests/root-filesystem.test.mjs
```
