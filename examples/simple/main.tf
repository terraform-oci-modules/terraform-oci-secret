provider "oci" {}

locals {
  name = "ex-simple"

  tags = {
    Example    = local.name
    GithubRepo = "terraform-oci-secret"
    GithubOrg  = "terraform-oci-modules"
  }
}

################################################################################
# One secret with a literal value, in an existing vault.
################################################################################

module "secret" {
  source = "../../"

  compartment_id = var.compartment_id
  vault_id       = var.vault_id
  key_id         = var.key_id

  secrets = {
    "${local.name}-db-password" = {
      description = "Application database password"
      content     = "s3cr3t-do-not-commit"
    }
  }

  tags = local.tags
}
