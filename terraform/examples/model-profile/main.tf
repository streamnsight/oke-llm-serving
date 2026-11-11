module "model_profile" {
  enable_external_analysis = true # Local/prepared runner only; RMS should use the runtime-free example.
  source                   = "../../modules/model-profile"
  model                    = "Qwen/Qwen2.5-0.5B-Instruct"
  revision                 = "main" # Replace with profile.model.resolved_revision after discovery.
  context_length           = 4096
  concurrency              = 4
}

output "profile" {
  value = module.model_profile.profile
}
