<!-- Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved. -->
<!-- Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl. -->
# Generic Artifact repository cleanup

The owning repository calls scripts/cleanup-repository.sh from its destroy-time local-exec provisioner, passing only self.id and self.compartment_id. It purges every version in that exact repository, including untracked historical versions, and polls until empty before Terraform deletes the repository. A list/delete failure stops repository deletion and preserves the failing exit status.

This is a shared runtime asset, not a pipeline or an independent Terraform resource. Both publishers must include this directory in generated bundles. Cleanup runs only during destruction of an owned repository; routine Plan/Apply does not purge artifacts. Model weights in Object Storage or PVCs are outside its scope.
