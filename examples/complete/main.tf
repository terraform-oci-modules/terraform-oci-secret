provider "oci" {}

locals {
  name = "ex-complete"

  tags = {
    Example    = local.name
    GithubRepo = "terraform-oci-secret"
    GithubOrg  = "terraform-oci-modules"
  }
}

################################################################################
# A mix of secrets in an existing vault.
################################################################################

module "secret" {
  source = "../../"

  compartment_id = var.compartment_id
  vault_id       = var.vault_id
  key_id         = var.key_id

  secrets = {
    # Literal value.
    "${local.name}-api-token" = {
      description = "Third-party API token"
      content     = "token-value-goes-here"
      metadata = {
        endpoint = "https://api.example.com"
      }
    }

    # OCI generates a passphrase; nothing sensitive passes through Terraform.
    "${local.name}-service-account" = {
      description = "Generated service-account passphrase"
      generation = {
        generation_type     = "PASSPHRASE"
        generation_template = "SECRETS_DEFAULT_PASSWORD"
        passphrase_length   = 24
      }
    }

    # Literal value that expires and must be refreshed every 30 days.
    "${local.name}-signing-key" = {
      description = "Short-lived signing key"
      content     = "rotate-me-every-month"
      expiry_rule = {
        version_expiry_interval           = "P30D"
        block_content_retrieval_on_expiry = true
      }
    }

    # A secret rotated by an OCI Function - Terraform seeds it once, then leaves
    # secret_content alone (the rotation config routes it to the ignore path).
    "${local.name}-rotated" = {
      description = "Rotated by a function"
      content     = "initial-value"
      rotation = {
        target_system_type            = "FUNCTION"
        function_id                   = var.rotation_function_id
        rotation_interval             = "P45D"
        is_scheduled_rotation_enabled = true
      }
    }
  }

  tags = local.tags
}
