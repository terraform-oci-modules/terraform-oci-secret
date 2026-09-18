# Mock test for examples/rotation. No real OCI resources, no credentials.

mock_provider "oci" {}

variables {
  compartment_id = "ocid1.compartment.oc1..aaaaaaaamockrotation"
  vault_id       = "ocid1.vault.oc1.iad.aaaaaaaamockvault"
  key_id         = "ocid1.key.oc1.iad.aaaaaaaamockkey"
  adb_id         = "ocid1.autonomousdatabase.oc1..aaaaaaaamockadb"
}

run "rotation_example" {
  command = apply

  module {
    source = "./examples/rotation"
  }

  assert {
    condition     = output.secret_id != null
    error_message = "the rotated secret must be created"
  }
}
