mock_provider "oci" {}
mock_provider "http" {}
mock_provider "oci" {
  alias = "us_chicago_1"
}
variables {
  tenancy_ocid = "test-root"
  region       = "us-chicago-1"
  model        = "org/model"
}
override_module {
  target  = module.model_profile
  outputs = { profile = { memory = { status = "unsupported" } } }
}

run "unmapped_subscription_fails" {
  command = plan
  override_data {
    target = data.oci_identity_region_subscriptions.subscribed
    values = { region_subscriptions = [{ region_name = "new-region-1", state = "READY" }] }
  }
  expect_failures = [output.discovery]
}

run "select_ready_subscriptions" {
  command = plan
  override_data {
    target = data.oci_identity_region_subscriptions.subscribed
    values = { region_subscriptions = [{ region_name = "us-chicago-1", state = "READY" }, { region_name = "us-ashburn-1", state = "IN_PROGRESS" }] }
  }
  override_module {
    target = module.us_chicago_1[0]
    outputs = {
      result    = { region = "us-chicago-1", availability_domains = [] }
      inventory = { region = "us-chicago-1", limits = [] }
    }
  }
  assert {
    condition     = output.discovery.assessed_regions == tolist(["us-chicago-1"]) && length(output.discovery.regions) == 1
    error_message = "Only READY subscriptions should activate regional modules."
  }
}
