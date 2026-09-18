################################################################################
# Mock unit tests: fast, free, no real OCI resources.
#
# Exercises input->config mapping (content vs generation, the managed vs
# ignore-content split, key_id fallback, secret_rules, tag merge) against the
# module root with a mocked OCI provider. Every validation block has a matching
# reject case. Run on its own:
#   terraform test -filter=tests/unit_mappings.tftest.hcl
################################################################################

mock_provider "oci" {}

variables {
  compartment_id = "ocid1.compartment.oc1..aaaaaaaaunitcompartment"
  vault_id       = "ocid1.vault.oc1.iad.aaaaaaaaunitvault"
  key_id         = "ocid1.key.oc1.iad.aaaaaaaaunitkey"
}

# --- content vs generation -------------------------------------------------

run "literal_content_is_base64_encoded" {
  command = plan

  variables {
    secrets = {
      s1 = { content = "hunter2" }
    }
  }

  assert {
    condition     = one(oci_vault_secret.this["s1"].secret_content[*].content) == base64encode("hunter2")
    error_message = "content must be base64-encoded into secret_content.content"
  }
  assert {
    condition     = one(oci_vault_secret.this["s1"].secret_content[*].content_type) == "BASE64"
    error_message = "content_type must be BASE64"
  }
  assert {
    condition     = length(oci_vault_secret.ignore_content) == 0
    error_message = "a plain literal secret must be in the managed (this) resource"
  }
}

run "generation_sets_auto_generation_and_no_content" {
  command = plan

  variables {
    secrets = {
      s1 = {
        generation = {
          generation_type     = "PASSPHRASE"
          generation_template = "SECRETS_DEFAULT_PASSWORD"
          passphrase_length   = 20
        }
      }
    }
  }

  assert {
    condition     = oci_vault_secret.this["s1"].enable_auto_generation == true
    error_message = "generation must set enable_auto_generation = true"
  }
  assert {
    condition     = length(oci_vault_secret.this["s1"].secret_content) == 0
    error_message = "a generated secret must not carry a secret_content block"
  }
  assert {
    condition     = one(oci_vault_secret.this["s1"].secret_generation_context[*].generation_type) == "PASSPHRASE"
    error_message = "generation_type must reach the secret_generation_context block"
  }
}

run "generation_template_valid_per_type" {
  command = plan

  variables {
    secrets = {
      ssh   = { generation = { generation_type = "SSH_KEY", generation_template = "RSA_4096" } }
      bytes = { generation = { generation_type = "BYTES", generation_template = "BYTES_1024" } }
    }
  }

  assert {
    condition     = one(oci_vault_secret.this["ssh"].secret_generation_context[*].generation_template) == "RSA_4096"
    error_message = "a valid SSH_KEY template must be accepted"
  }
  assert {
    condition     = one(oci_vault_secret.this["bytes"].secret_generation_context[*].generation_template) == "BYTES_1024"
    error_message = "a valid BYTES template must be accepted"
  }
}

# --- managed vs ignore-content split -------------------------------------

run "rotation_routes_secret_to_ignore_content" {
  command = plan

  variables {
    secrets = {
      plain = { content = "a" }
      rot = {
        content = "seed"
        rotation = {
          target_system_type = "FUNCTION"
          function_id        = "ocid1.fnfunc.oc1..aaaaaaaafn"
          rotation_interval  = "P30D"
        }
      }
    }
  }

  assert {
    condition     = contains(keys(oci_vault_secret.this), "plain") && !contains(keys(oci_vault_secret.this), "rot")
    error_message = "a secret with rotation must not be in the managed resource"
  }
  assert {
    condition     = contains(keys(oci_vault_secret.ignore_content), "rot")
    error_message = "a secret with rotation must be in the ignore-content resource"
  }
  assert {
    condition     = one(oci_vault_secret.ignore_content["rot"].rotation_config[*].rotation_interval) == "P30D"
    error_message = "rotation_interval must reach the rotation_config block"
  }
}

run "module_ignore_flag_routes_all_secrets" {
  command = plan

  variables {
    ignore_content_changes = true
    secrets = {
      s1 = { content = "a" }
      s2 = { content = "b" }
    }
  }

  assert {
    condition     = length(oci_vault_secret.this) == 0 && length(oci_vault_secret.ignore_content) == 2
    error_message = "ignore_content_changes = true must route every secret to the ignore-content resource"
  }
}

# --- key_id fallback ---------------------------------------------------

run "per_secret_key_id_overrides_module_key_id" {
  command = plan

  variables {
    secrets = {
      s1 = { content = "a" }
      s2 = { content = "b", key_id = "ocid1.key.oc1.iad.aaaaaaaaother" }
    }
  }

  assert {
    condition     = oci_vault_secret.this["s1"].key_id == "ocid1.key.oc1.iad.aaaaaaaaunitkey"
    error_message = "a secret with no key_id must use the module-level key_id"
  }
  assert {
    condition     = oci_vault_secret.this["s2"].key_id == "ocid1.key.oc1.iad.aaaaaaaaother"
    error_message = "secrets[*].key_id must override the module-level key_id"
  }
}

run "missing_key_id_fails_precondition" {
  command = plan

  variables {
    key_id  = null
    secrets = { s1 = { content = "a" } }
  }

  expect_failures = [oci_vault_secret.this]
}

# --- secret_rules -----------------------------------------------------

run "expiry_and_reuse_rules_map_to_secret_rules" {
  command = plan

  variables {
    secrets = {
      s1 = {
        content     = "a"
        expiry_rule = { version_expiry_interval = "P7D", block_content_retrieval_on_expiry = true }
        reuse_rule  = { enforce_on_deleted_versions = true }
      }
    }
  }

  assert {
    condition     = length(oci_vault_secret.this["s1"].secret_rules) == 2
    error_message = "expiry_rule and reuse_rule must produce two secret_rules blocks"
  }
  assert {
    condition     = contains([for r in oci_vault_secret.this["s1"].secret_rules : r.rule_type], "SECRET_EXPIRY_RULE")
    error_message = "an expiry_rule must produce a SECRET_EXPIRY_RULE"
  }
  assert {
    condition     = contains([for r in oci_vault_secret.this["s1"].secret_rules : r.rule_type], "SECRET_REUSE_RULE")
    error_message = "a reuse_rule must produce a SECRET_REUSE_RULE"
  }
}

# --- tag merge -------------------------------------------------------

run "entry_tags_merge_over_module_tags" {
  command = plan

  variables {
    tags = { Owner = "platform", Managed = "terraform" }
    secrets = {
      s1 = { content = "a", tags = { Owner = "data", Extra = "yes" } }
    }
  }

  assert {
    condition     = oci_vault_secret.this["s1"].freeform_tags["Owner"] == "data"
    error_message = "per-secret tags must win over module-wide tags of the same key"
  }
  assert {
    condition     = oci_vault_secret.this["s1"].freeform_tags["Managed"] == "terraform"
    error_message = "module-wide tags must still apply where not overridden"
  }
}

# --- create = false --------------------------------------------------

run "create_false_makes_no_resources" {
  command = plan

  variables {
    create  = false
    secrets = { s1 = { content = "a" }, s2 = { content = "b", rotation = { target_system_type = "ADB", adb_id = "ocid1.autonomousdatabase.oc1..aaaa", rotation_interval = "P30D" } } }
  }

  assert {
    condition     = length(oci_vault_secret.this) == 0 && length(oci_vault_secret.ignore_content) == 0
    error_message = "create = false must produce zero resources"
  }
}

################################################################################
# Negative paths: every validation block has a reject case.
################################################################################

run "rejects_bad_compartment_id" {
  command = plan
  variables { compartment_id = "not-an-ocid" }
  expect_failures = [var.compartment_id]
}

run "rejects_bad_vault_id" {
  command = plan
  variables { vault_id = "ocid1.compartment.oc1..aaaa" }
  expect_failures = [var.vault_id]
}

run "rejects_bad_key_id" {
  command = plan
  variables { key_id = "ocid1.vault.oc1..aaaa" }
  expect_failures = [var.key_id]
}

run "rejects_bad_secret_name" {
  command = plan
  variables { secrets = { "bad name" = { content = "a" } } }
  expect_failures = [var.secrets]
}

run "rejects_content_and_generation" {
  command = plan
  variables {
    secrets = {
      s1 = { content = "a", generation = { generation_type = "BYTES", generation_template = "BYTES_512" } }
    }
  }
  expect_failures = [var.secrets]
}

run "rejects_neither_content_nor_generation" {
  command = plan
  variables { secrets = { s1 = { description = "empty" } } }
  expect_failures = [var.secrets]
}

run "rejects_passphrase_length_on_non_passphrase" {
  command = plan
  variables {
    secrets = {
      s1 = { generation = { generation_type = "SSH_KEY", generation_template = "RSA_2048", passphrase_length = 20 } }
    }
  }
  expect_failures = [var.secrets]
}

run "rejects_bad_generation_type" {
  command = plan
  variables {
    secrets = { s1 = { generation = { generation_type = "RSA_KEY", generation_template = "RSA_2048" } } }
  }
  expect_failures = [var.secrets]
}

run "rejects_generation_template_mismatch" {
  command = plan
  variables {
    secrets = {
      passphrase_gets_ssh_template = { generation = { generation_type = "PASSPHRASE", generation_template = "RSA_2048" } }
    }
  }
  expect_failures = [var.secrets]
}

run "rejects_bad_rotation_target" {
  command = plan
  variables {
    secrets = { s1 = { content = "a", rotation = { target_system_type = "LAMBDA", rotation_interval = "P30D" } } }
  }
  expect_failures = [var.secrets]
}

run "rejects_rotation_adb_without_adb_id" {
  command = plan
  variables {
    secrets = { s1 = { content = "a", rotation = { target_system_type = "ADB", rotation_interval = "P30D" } } }
  }
  expect_failures = [var.secrets]
}

run "rejects_rotation_function_without_function_id" {
  command = plan
  variables {
    secrets = { s1 = { content = "a", rotation = { target_system_type = "FUNCTION", rotation_interval = "P30D" } } }
  }
  expect_failures = [var.secrets]
}

run "rejects_rotation_interval_out_of_range" {
  command = plan
  variables {
    secrets = { s1 = { content = "a", rotation = { target_system_type = "FUNCTION", function_id = "ocid1.fnfunc.oc1..a", rotation_interval = "P400D" } } }
  }
  expect_failures = [var.secrets]
}

run "rejects_expiry_interval_out_of_range" {
  command = plan
  variables {
    secrets = { s1 = { content = "a", expiry_rule = { version_expiry_interval = "P120D" } } }
  }
  expect_failures = [var.secrets]
}

run "rejects_expiry_both_forms" {
  command = plan
  variables {
    secrets = { s1 = { content = "a", expiry_rule = { version_expiry_interval = "P7D", time_of_absolute_expiry = "2027-01-01T00:00:00Z" } } }
  }
  expect_failures = [var.secrets]
}

run "rejects_bad_absolute_expiry" {
  command = plan
  variables {
    secrets = { s1 = { content = "a", expiry_rule = { time_of_absolute_expiry = "2027-01-01" } } }
  }
  expect_failures = [var.secrets]
}

run "rejects_empty_replication_targets" {
  command = plan
  variables {
    secrets = { s1 = { content = "a", replication = { targets = [] } } }
  }
  expect_failures = [var.secrets]
}
