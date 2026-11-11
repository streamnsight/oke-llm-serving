module "model_profile" {
  source         = "../../modules/model-profile"
  model          = "Qwen/Qwen2.5-0.5B-Instruct"
  revision       = "main" # Replace with profile.model.resolved_revision after discovery.
  context_length = 4096
  concurrency    = 4
}

output "profile" {
  value = module.model_profile.profile
}
