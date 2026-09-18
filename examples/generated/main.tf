provider "oci" {}

locals {
  name = "ex-generated"

  tags = {
    Example    = local.name
    GithubRepo = "terraform-oci-secret"
    GithubOrg  = "terraform-oci-modules"
  }
}

################################################################################
# Secrets whose values OCI generates. No secret material passes through
# Terraform or lands in state.
################################################################################

module "secret" {
  source = "../../"

  compartment_id = var.compartment_id
  vault_id       = var.vault_id
  key_id         = var.key_id

  secrets = {
    "${local.name}-passphrase" = {
      description = "Generated passphrase"
      generation = {
        generation_type     = "PASSPHRASE"
        generation_template = "SECRETS_DEFAULT_PASSWORD"
        passphrase_length   = 32
      }
    }

    "${local.name}-ssh-key" = {
      description = "Generated 4096-bit SSH key pair (PEM)"
      generation = {
        generation_type     = "SSH_KEY"
        generation_template = "RSA_4096"
      }
    }

    "${local.name}-bytes" = {
      description = "Generated random bytes, base64"
      generation = {
        generation_type     = "BYTES"
        generation_template = "BYTES_512"
      }
    }
  }

  tags = local.tags
}
