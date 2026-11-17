<!--
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->

This module declares independent OCI DevOps pipelines for shared Kubernetes
components. It does not create GPU nodes, IAM policies, Kubernetes RBAC, a DevOps
project, or the OKE deployment environment. The caller owns those resources and
passes an existing immutable source Generic Artifact Registry repository for required file inputs.
No provider aliases are required.

Each component declares `mode`, `namespace`, `release_name`, `ownership_token`,
`chart = { repository, name, version }` and optional `values_yaml`, `parameters`,
`dependencies`, `blocker_kinds`, `crd_names`, `deployment_names`, `timeout_seconds`.
Use a stable ownership token derived from the platform and cluster, not a run ID.
`repository` is an HTTPS chart repository or an OCI repository prefix excluding
the chart name. `values_yaml` is a string, allowing components with different
value structures. Optional parameter placeholders use `${PARAMETER}`; escape
them as `$${PARAMETER}` inside Terraform strings. Parameters contain no secrets.

A trusted adapter may supply `chart.files`, a map of relative chart filenames
to UTF-8 source, instead of `chart.repository`. Those inputs are checksum-verified
Artifact Registry files. Prepare normalizes permissions, sort order and mtimes
with GNU tar and `gzip -n`, then imports the reproducible archive into OCIR.
Local chart versions are frozen with their source: changing `CHART_VERSION`
alone fails before native Helm. A source update requires Terraform apply.
Every source artifact path is prefixed by the caller's unique `name` so that
independent Terraform states sharing a repository do not own the same artifact.

| Mode | Deploy/validate pipeline | Explicit undeploy pipeline |
|---|---|---|
| `managed` | Shell prepare → native Helm install/upgrade → Shell validation | Yes, defaults to uninstall with ownership checks |
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
Small scripts, specifications and command specifications use readable inline
command specs; values use inline Generic File artifacts. Required runtime/chart
source files use Generic Artifact inputs; chart packages belong in OCIR. `registry_host` supports an explicit
realm-specific OCIR endpoint; the default is commercial `${region}.ocir.io`.
Prepare creates the namespace by default. `namespace_mode="existing"` instead
checks it without mutation; trusted adapter preflight is responsible for its
ownership/onboarding check. `manage_crds=false` disables both Shell CRD updates
and native CRD installation. Service-only `OCI_` controls are not declared as
pipeline parameters; `ENFORCE_HELM_DEPLOYMENT` remains the editable rerun argument.
Chart delivery passes the OCI-issued short-lived bearer token directly through
a private Helm registry configuration (`registrytoken`), avoiding a second Basic
credential exchange. The token never enters command arguments or result
artifacts; temporary credential files are removed on exit.

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

A Kubernetes Lease in `lock_namespace` (default `kube-system`), keyed by cluster/namespace/release, serializes
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

Trusted caller `runtime_files` are immutable source inputs under `runtime/`.
Fixed `preflight.sh`, `validate.sh` and `retired.sh` hooks run under that same
lease before install, before ready evidence, and after uninstall respectively.
These are reviewed adapter source files, not command strings in component
metadata. `non_release_parameters` identifies probe-only parameters that do not
alter a Helm release; all other parameters contribute to its settings hash.

If native Helm fails or a Shell stage is killed, the lock remains deliberately.
Expiry never permits automatic takeover. Inspect the deployment and release;
then explicitly pass `RECOVER_LOCK_HOLDER` equal to the old deployment OCID. The
runner also requires the lease duration to have elapsed and OCI to report that
deployment as `SUCCEEDED`, `FAILED` or `CANCELED`. It refuses pending, active or
unreadable deployments. Dedicated undeploy pipelines default `CONFIRM_UNINSTALL`
to `true`; selecting that pipeline is sufficient to uninstall. An explicit
`false` override still prevents uninstall.

Every Shell operation prints its structured JSON summary to stdout for DevOps
Logging, including effective non-secret parameters, their SHA-256, generation,
deployment/pipeline IDs and status. Routine reporting needs no Artifact Registry
upload permission and preserves the primary failure exit code. A prepared result
is not readiness: check the OCI deployment result and fresh controller state.
The caller owns execution, source-file retention and repository retirement; the
OCI generic upload resource does not delete stored versions automatically.

Official contracts: [native Helm stages](https://docs.oracle.com/en-us/iaas/Content/devops/using/deploy-helmchart.htm),
[OCIR chart artifacts](https://docs.oracle.com/en-us/iaas/Content/devops/using/add-helmchart.htm),
[Generic Artifact inputs](https://docs.oracle.com/en-us/iaas/Content/devops/using/artifact_registry_artifact.htm),
[Shell command specification](https://docs.oracle.com/en-us/iaas/Content/devops/using/command_spec.htm),
[Helm CRD lifecycle](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/).
