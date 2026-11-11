# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
module "model_profile" {
  source         = "../../modules/model-profile"
  model          = "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct"
  revision       = "main" # Pin profile.model.resolved_revision after discovery.
  context_length = 4096
  concurrency    = 4
}

output "profile" {
  value = module.model_profile.profile
}
