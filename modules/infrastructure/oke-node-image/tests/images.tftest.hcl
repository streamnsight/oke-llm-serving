# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
mock_provider "oci" {
  mock_data "oci_containerengine_node_pool_option" {
    defaults = {
      shapes = ["VM.GPU.A10.1", "VM.Standard.E4.Flex"]
      sources = [
        {
          image_id = "old", source_name = "Oracle-Linux-8.10-Gen2-GPU-2026.08.01-0-OKE-1.34.1-1", source_type = "IMAGE"
        },
        {
          image_id = "new", source_name = "Oracle-Linux-8.10-Gen2-GPU-2026.09.01-0-OKE-1.34.1-2", source_type = "IMAGE"
        },
        {
          image_id = "wrong-version", source_name = "Oracle-Linux-8.10-Gen2-GPU-2026.09.01-0-OKE-1.35.1-2", source_type = "IMAGE"
        },
        {
          image_id = "cpu", source_name = "Oracle-Linux-8.10-2026.09.01-0-OKE-1.34.1-2", source_type = "IMAGE"
        },
        {
          image_id = "arm", source_name = "Oracle-Linux-8.10-aarch64-2026.09.01-0-OKE-1.34.1-2", source_type = "IMAGE"
        }
      ]
    }
  }
  mock_data "oci_core_image" {
    defaults = {
      state = "AVAILABLE", display_name = "Oracle-Linux-8.10-Gen2-GPU-2026.08.01-0-OKE-1.34.1-1", time_created = "2026-08-01T00:00:00Z"
    }
  }
  mock_data "oci_core_image_shapes" {
    defaults = {
      image_shape_compatibilities = [{
        shape = "VM.GPU.A10.1"
        }
        , {
          shape = "VM.Standard.E4.Flex"
        }
      ]
    }
  }
}
variables {
  cluster_id         = "cluster"
  compartment_id     = "target"
  kubernetes_version = "v1.34.1"
  shape              = "VM.GPU.A10.1"
  architecture       = "amd64"
  os_version         = "8"
}
override_data {
  target = data.oci_core_image.candidate["new"]
  values = {
    state = "AVAILABLE", display_name = "Oracle-Linux-8.10-Gen2-GPU-2026.09.01-0-OKE-1.34.1-2", time_created = "2026-09-01T00:00:00Z"
  }
}
run "newest_exact_oke_gpu_version" {
  command = plan
  assert {
    condition     = output.image.id == "new" && length(local.sources) == 2
    error_message = "Filter OS, GPU/CPU architecture and exact Kubernetes version, then choose newest compatible metadata."
  }
}
run "shape_incompatible_newest_falls_back" {
  command = plan
  override_data {
    target = data.oci_core_image_shapes.candidate["new"]
    values = {
      image_shape_compatibilities = [{
        shape = "VM.Standard.E4.Flex"
        }
      ]
    }
  }
  assert {
    condition     = output.image.id == "old"
    error_message = "A newer image must not win if it cannot launch the selected shape."
  }
}
run "cpu_sources_exclude_gpu_and_arm" {
  command = plan
  variables {
    shape = "VM.Standard.E4.Flex"
  }
  assert {
    condition     = output.image.id == "cpu"
    error_message = "CPU image selection must exclude NVIDIA and ARM images."
  }
}
run "explicit_override_is_still_shape_checked" {
  command = plan
  variables {
    image_id = "custom"
  }
  assert {
    condition     = output.image.id == "custom" && output.image.source == "explicit_override"
    error_message = "Support explicit image OCIDs without skipping metadata and shape checks."
  }
}
run "no_matching_version_is_an_explicit_preview_issue" {
  command = plan
  variables {
    kubernetes_version = "v9.99.0"
  }
  assert {
    condition     = output.image.id == null && output.image.status == "no_compatible_image"
    error_message = "Do not silently fall back to a platform image or different OKE version."
  }
}
