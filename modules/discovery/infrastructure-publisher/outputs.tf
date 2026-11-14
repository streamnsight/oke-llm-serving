# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
output "artifact_location" {
  description = "Existing discovery ZIP/report publication context; no pipeline software or model data belongs here."
  value = {
    namespace = data.oci_objectstorage_namespace.artifacts[0].namespace, bucket = oci_objectstorage_bucket.artifacts[0].name,
    region    = var.region, published_at = local.published_at
  }
}
