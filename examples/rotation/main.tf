provider "oci" {}

locals {
  name = "ex-rotation"

  tags = {
    Example    = local.name
    GithubRepo = "terraform-oci-secret"
    GithubOrg  = "terraform-oci-modules"
  }
}

################################################################################
# A secret rotated by OCI against an Autonomous Database on a schedule.
#
# Needs a real ADB OCID, so this example is exercised with `terraform plan`
# only. Because the secret has a rotation config, the module seeds the content
# once and then ignores secret_content (rotation changes it out of band).
################################################################################

module "secret" {
  source = "../../"

  compartment_id = var.compartment_id
  vault_id       = var.vault_id
  key_id         = var.key_id

  secrets = {
    "${local.name}-adb-wallet-password" = {
      description = "ADB admin password, rotated by OCI"
      content     = "seed-value-replaced-on-first-rotation"
      rotation = {
        target_system_type            = "ADB"
        adb_id                        = var.adb_id
        rotation_interval             = "P60D"
        is_scheduled_rotation_enabled = true
      }
    }
  }

  tags = local.tags
}
