<!--
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

This module declares independent OCI DevOps pipelines for shared Kubernetes
components. It does not create GPU nodes, IAM policies, Kubernetes RBAC, a DevOps
project, or the OKE deployment environment. The caller owns those resources and
passes existing immutable source and result Generic Artifact Registry repositories.
No provider aliases are required.

Each component declares `mode`, `namespace`, `release_name`, `ownership_token`,
`chart = { repository, name, version }` and optional `values_yaml`, `parameters`,
`dependencies`, `blocker_kinds`, `crd_names`, `deployment_names`, `timeout_seconds`.
Use a stable ownership token derived from the platform and cluster, not a run ID.
`repository` is an HTTPS chart repository or an OCI repository prefix excluding
the chart name. `values_yaml` is a string, allowing components with different
value structures. Optional parameter placeholders use `${PARAMETER}`; escape
them as `$${PARAMETER}` inside Terraform strings. Parameters contain no secrets.

| Mode | Deploy/validate pipeline | Explicit undeploy pipeline |
|---|---|---|
| `managed` | Shell prepare → native Helm install/upgrade → Shell validation | Yes, confirmation and ownership guarded |
| `reuse` | Read-only Helm/controller validation and result artifact | No |
| `retire` | None | Retained until the owner removes it |

Changing mode requires Terraform apply. Preflight success cannot skip a native
Helm stage. Reuse therefore omits the mutating stage entirely. Removing an entry
or destroying Terraform pipeline definitions never uninstalls its release.
Set `retire` and run its explicit undeploy pipeline before disabling a managed
component. Omitting it removes the undeploy definition too; if that happened,
reapply the same component key, namespace, release and ownership token in
`retire` mode to restore the guarded cleanup path.

Managed prepare mirrors the requested upstream chart into a private OCIR
repository, then lets the native `OKE_HELM_CHART_DEPLOYMENT` stage install it.
`CHART_VERSION` is editable: both mirroring and native artifact resolution use
that same parameter. Existing mirrored versions are compared against upstream
and never deliberately overwritten. Shell does not run Helm install or upgrade.
Values, scripts, specifications and command specifications are immutable Generic
Artifacts; chart content belongs in OCIR. `registry_host` supports an explicit
realm-specific OCIR endpoint; the default is commercial `${region}.ocir.io`.

Raw CRDs in the chart's `crds/` directory are created with stable ownership and
keep annotations before native installation. Updates require that ownership and
use server-side apply without forcing field conflicts. Existing external CRDs
are refused: use the external controller through reuse or resolve ownership
outside the pipeline. Templated CRDs and PVCs must carry
`helm.sh/resource-policy: keep`; otherwise prepare and uninstall refuse the chart.
Namespaced model custom resources are deployed by the separate model stack.

The caller must grant each pipeline principal source artifact reads, result
artifact writes, access to its OCIR repositories and the selected cluster, the
documented Shell stage container/network permissions, and Kubernetes permissions
for its controller resources and coordination Leases. Recovery additionally
reads the prior OCI deployment. The shared native OKE environment needs private
API connectivity independently of the Shell stage network channel. Public chart
and helper binary downloads require network egress. Helper downloads verify
checksums; the Shell runner installs Helm 3, the cluster's matching kubectl and
a fixed checksum-verified yq binary. The native service controls its own Helm
runtime version.

`dependencies` checks prerequisite releases are deployed; it does not launch
their pipelines. An optional caller-owned coordinator can schedule independent
components in parallel after their prerequisites. `blocker_kinds` names served
Kubernetes API resource types (for example `scaledobjects.keda.sh`). Uninstall
refuses external instances, excluding only exact API version/kind/namespace/name
identities in its own Helm release manifest. Missing APIs are skipped; discovery
and read failures fail closed. Keep CRDs, PVCs, namespaces and node pools separate
from explicit release uninstall. Chart hooks must also follow that retention
contract; the runner does not execute arbitrary metadata commands.

A Kubernetes Lease in `kube-system`, keyed by cluster/namespace/release, serializes
managed install, upgrade and uninstall across pipelines. Acquisition and release
use resourceVersion compare-and-swap. Prepare retains the lock across the bounded
native Helm stage; finish verifies the same deployment, generation, parameter
hash, installed chart/version and effective Helm values before marking ready.
This is an advisory lock for cooperating pipelines, not a Kubernetes API lock
against unrelated administrators. All Shell/native stages have bounded timeouts.
The documented predefined `OCI_DEPLOYMENT_ID` is explicitly bound through the
command-spec environment and exported into child scripts. If the runtime fails
to provide it, the component refuses to mutate resources; independent random
fallbacks cannot safely correlate prepare and finish across a native stage.

If native Helm fails or a Shell stage is killed, the lock remains deliberately.
Expiry never permits automatic takeover. Inspect the deployment and release;
then explicitly pass `RECOVER_LOCK_HOLDER` equal to the old deployment OCID. The
runner also requires the lease duration to have elapsed and OCI to report that
deployment as `SUCCEEDED`, `FAILED` or `CANCELED`. It refuses pending, active or
unreadable deployments. Undeploy separately requires `CONFIRM_UNINSTALL=true`.

Every Shell operation uploads immutable JSON evidence to the results repository
at `<name>/components/<component>/<generation>/<OCI_DEPLOYMENT_ID>/<operation>.json`,
with a timestamp/random artifact version. It records effective non-secret
parameters, their SHA-256, generation, deployment/pipeline IDs and status. A
prepared result is not readiness. Native failure may have no finish artifact;
consumers must check the OCI deployment result as well as fresh controller state
and evidence. Terraform outputs desired configuration and pipeline identifiers,
not a claim of runtime readiness. Source/result artifact retention and repository
retirement are caller-owned; the OCI generic upload resource does not delete
stored versions automatically.

Official contracts: [native Helm stages](https://docs.oracle.com/en-us/iaas/Content/devops/using/deploy-helmchart.htm),
[OCIR chart artifacts](https://docs.oracle.com/en-us/iaas/Content/devops/using/add-helmchart.htm),
[Generic Artifact inputs](https://docs.oracle.com/en-us/iaas/Content/devops/using/artifact_registry_artifact.htm),
[Shell command specification](https://docs.oracle.com/en-us/iaas/Content/devops/using/command_spec.htm),
[Helm CRD lifecycle](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/).
