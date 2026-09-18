locals {
  create = var.create

  secrets = local.create ? var.secrets : {}

  # A secret whose content Terraform keeps reconciling vs. one it leaves alone
  # after create. Rotation always implies "leave alone" (the target system
  # changes the value out of band); var.ignore_content_changes forces it for all.
  managed_secrets = {
    for k, v in local.secrets : k => v
    if !(var.ignore_content_changes || v.rotation != null)
  }
  ignored_secrets = {
    for k, v in local.secrets : k => v
    if var.ignore_content_changes || v.rotation != null
  }

  all_secrets = merge(oci_vault_secret.this, oci_vault_secret.ignore_content)
}

################################################################################
# Secrets - Terraform reconciles the content
################################################################################

resource "oci_vault_secret" "this" {
  for_each = local.managed_secrets

  compartment_id = var.compartment_id
  vault_id       = var.vault_id
  key_id         = try(coalesce(each.value.key_id, var.key_id), null)
  secret_name    = each.key
  description    = each.value.description
  metadata       = each.value.metadata

  enable_auto_generation = each.value.generation != null ? true : null

  dynamic "secret_content" {
    for_each = each.value.content != null ? [each.value.content] : []
    content {
      content_type = "BASE64"
      content      = sensitive(base64encode(secret_content.value))
    }
  }

  dynamic "secret_generation_context" {
    for_each = each.value.generation != null ? [each.value.generation] : []
    content {
      generation_type     = secret_generation_context.value.generation_type
      generation_template = secret_generation_context.value.generation_template
      passphrase_length   = secret_generation_context.value.passphrase_length
      secret_template     = secret_generation_context.value.secret_template
    }
  }

  dynamic "secret_rules" {
    for_each = each.value.expiry_rule != null ? [each.value.expiry_rule] : []
    content {
      rule_type                                     = "SECRET_EXPIRY_RULE"
      secret_version_expiry_interval                = secret_rules.value.version_expiry_interval
      time_of_absolute_expiry                       = secret_rules.value.time_of_absolute_expiry
      is_secret_content_retrieval_blocked_on_expiry = secret_rules.value.block_content_retrieval_on_expiry
    }
  }

  dynamic "secret_rules" {
    for_each = each.value.reuse_rule != null ? [each.value.reuse_rule] : []
    content {
      rule_type                              = "SECRET_REUSE_RULE"
      is_enforced_on_deleted_secret_versions = secret_rules.value.enforce_on_deleted_versions
    }
  }

  dynamic "replication_config" {
    for_each = each.value.replication != null ? [each.value.replication] : []
    content {
      is_write_forward_enabled = replication_config.value.is_write_forward_enabled
      dynamic "replication_targets" {
        for_each = replication_config.value.targets
        content {
          target_key_id   = replication_targets.value.target_key_id
          target_region   = replication_targets.value.target_region
          target_vault_id = replication_targets.value.target_vault_id
        }
      }
    }
  }

  freeform_tags = merge(var.tags, each.value.tags)
  defined_tags  = merge(var.defined_tags, each.value.defined_tags)

  dynamic "timeouts" {
    for_each = each.value.timeouts != null ? [each.value.timeouts] : []
    content {
      create = timeouts.value.create
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }

  lifecycle {
    precondition {
      condition     = try(coalesce(each.value.key_id, var.key_id), null) != null
      error_message = "secret \"${each.key}\" has no key_id: set secrets[\"${each.key}\"].key_id or the module-level key_id variable."
    }
    # OCI auto-injects Oracle-Tags into defined_tags; ignoring both tag maps
    # avoids perpetual drift. Matches terraform-oci-vault / terraform-oci-iam.
    ignore_changes = [defined_tags, freeform_tags]
  }
}

################################################################################
# Secrets - Terraform stops reconciling content after create
# (var.ignore_content_changes, or the secret has a rotation config)
################################################################################

resource "oci_vault_secret" "ignore_content" {
  for_each = local.ignored_secrets

  compartment_id = var.compartment_id
  vault_id       = var.vault_id
  key_id         = try(coalesce(each.value.key_id, var.key_id), null)
  secret_name    = each.key
  description    = each.value.description
  metadata       = each.value.metadata

  enable_auto_generation = each.value.generation != null ? true : null

  dynamic "secret_content" {
    for_each = each.value.content != null ? [each.value.content] : []
    content {
      content_type = "BASE64"
      content      = sensitive(base64encode(secret_content.value))
    }
  }

  dynamic "secret_generation_context" {
    for_each = each.value.generation != null ? [each.value.generation] : []
    content {
      generation_type     = secret_generation_context.value.generation_type
      generation_template = secret_generation_context.value.generation_template
      passphrase_length   = secret_generation_context.value.passphrase_length
      secret_template     = secret_generation_context.value.secret_template
    }
  }

  dynamic "rotation_config" {
    for_each = each.value.rotation != null ? [each.value.rotation] : []
    content {
      is_scheduled_rotation_enabled = rotation_config.value.is_scheduled_rotation_enabled
      rotation_interval             = rotation_config.value.rotation_interval
      target_system_details {
        target_system_type = rotation_config.value.target_system_type
        adb_id             = rotation_config.value.adb_id
        function_id        = rotation_config.value.function_id
      }
    }
  }

  dynamic "secret_rules" {
    for_each = each.value.expiry_rule != null ? [each.value.expiry_rule] : []
    content {
      rule_type                                     = "SECRET_EXPIRY_RULE"
      secret_version_expiry_interval                = secret_rules.value.version_expiry_interval
      time_of_absolute_expiry                       = secret_rules.value.time_of_absolute_expiry
      is_secret_content_retrieval_blocked_on_expiry = secret_rules.value.block_content_retrieval_on_expiry
    }
  }

  dynamic "secret_rules" {
    for_each = each.value.reuse_rule != null ? [each.value.reuse_rule] : []
    content {
      rule_type                              = "SECRET_REUSE_RULE"
      is_enforced_on_deleted_secret_versions = secret_rules.value.enforce_on_deleted_versions
    }
  }

  dynamic "replication_config" {
    for_each = each.value.replication != null ? [each.value.replication] : []
    content {
      is_write_forward_enabled = replication_config.value.is_write_forward_enabled
      dynamic "replication_targets" {
        for_each = replication_config.value.targets
        content {
          target_key_id   = replication_targets.value.target_key_id
          target_region   = replication_targets.value.target_region
          target_vault_id = replication_targets.value.target_vault_id
        }
      }
    }
  }

  freeform_tags = merge(var.tags, each.value.tags)
  defined_tags  = merge(var.defined_tags, each.value.defined_tags)

  dynamic "timeouts" {
    for_each = each.value.timeouts != null ? [each.value.timeouts] : []
    content {
      create = timeouts.value.create
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }

  lifecycle {
    precondition {
      condition     = try(coalesce(each.value.key_id, var.key_id), null) != null
      error_message = "secret \"${each.key}\" has no key_id: set secrets[\"${each.key}\"].key_id or the module-level key_id variable."
    }
    ignore_changes = [secret_content, defined_tags, freeform_tags]
  }
}
