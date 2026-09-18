module "wrapper" {
  source = "../"

  for_each = var.items

  compartment_id         = try(each.value.compartment_id, var.defaults.compartment_id)
  create                 = try(each.value.create, var.defaults.create, true)
  defined_tags           = try(each.value.defined_tags, var.defaults.defined_tags, {})
  ignore_content_changes = try(each.value.ignore_content_changes, var.defaults.ignore_content_changes, false)
  key_id                 = try(each.value.key_id, var.defaults.key_id, null)
  secrets                = try(each.value.secrets, var.defaults.secrets, {})
  tags                   = try(each.value.tags, var.defaults.tags, {})
  vault_id               = try(each.value.vault_id, var.defaults.vault_id)
}
