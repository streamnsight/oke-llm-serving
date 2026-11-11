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
