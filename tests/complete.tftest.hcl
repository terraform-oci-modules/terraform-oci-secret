# Mock test for examples/complete. No real OCI resources, no credentials.

mock_provider "oci" {}

variables {
  compartment_id = "ocid1.compartment.oc1..aaaaaaaamockcomplete"
  vault_id       = "ocid1.vault.oc1.iad.aaaaaaaamockvault"
  key_id         = "ocid1.key.oc1.iad.aaaaaaaamockkey"
}

run "complete_example" {
  command = apply

  module {
    source = "./examples/complete"
  }

  assert {
    condition     = length(output.secret_ids) == 4
    error_message = "the example must create four secrets"
  }
  assert {
    condition     = output.secrets["ex-complete-rotated"].id != null
    error_message = "the rotated secret must be created (via the ignore-content path)"
  }
}
