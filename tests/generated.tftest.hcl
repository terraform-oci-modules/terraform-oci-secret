# Mock test for examples/generated. No real OCI resources, no credentials.

mock_provider "oci" {}

variables {
  compartment_id = "ocid1.compartment.oc1..aaaaaaaamockgenerated"
  vault_id       = "ocid1.vault.oc1.iad.aaaaaaaamockvault"
  key_id         = "ocid1.key.oc1.iad.aaaaaaaamockkey"
}

run "generated_example" {
  command = apply

  module {
    source = "./examples/generated"
  }

  assert {
    condition     = length(output.secret_ids) == 3
    error_message = "the example must create three generated secrets"
  }
}
