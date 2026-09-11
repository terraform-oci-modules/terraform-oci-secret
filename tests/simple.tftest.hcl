# Mock test for examples/simple. No real OCI resources, no credentials.

mock_provider "oci" {}

variables {
  compartment_id = "ocid1.compartment.oc1..aaaaaaaamocksimple"
  vault_id       = "ocid1.vault.oc1.iad.aaaaaaaamockvault"
  key_id         = "ocid1.key.oc1.iad.aaaaaaaamockkey"
}

run "simple_example" {
  command = apply

  module {
    source = "./examples/simple"
  }

  assert {
    condition     = output.secret_id != null
    error_message = "the example must expose the secret OCID"
  }
  assert {
    condition     = output.secret.secret_name == "ex-simple-db-password"
    error_message = "the curated secret output must carry the secret_name"
  }
}
