<!--
Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
-->
# Terraform module ownership

- `discovery/`: model and capacity assessment, recommendations and RMS bundle publication.
- `infrastructure/`: cluster/network/image lookup and retained GPU hosts.
- `cluster-add-ons/`: shared controller/component lifecycle and platform DevOps foundation.
- `llm-deployment/`: model-specific releases, validation, benchmarks, retirement and weight staging.
- `shared/`: delivery machinery used by both platform and model stages.

Scripts, charts and catalogs live under their owning module. Cross-group local references use relative source paths. Changing a model must not change retained pool resources; removing a pipeline definition does not uninstall its Helm release.
