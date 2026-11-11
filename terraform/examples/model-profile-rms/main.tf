variable "model_profile_json" {
  description = "Model profile generated beforehand by a pinned CLI/container and supplied as an RMS input."
  type        = string
}

module "model_profile" {
  source       = "../../modules/model-profile"
  profile_json = var.model_profile_json
}

output "profile" {
  value = module.model_profile.profile
}
