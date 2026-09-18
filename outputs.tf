output "secret_ids" {
  description = "Map of secret name => secret OCID"
  value       = { for k, s in local.all_secrets : k => s.id }
}

output "secrets" {
  description = "Map of secret name => curated attributes (id, secret_name, current_version_number, rotation_status, state, vault_id, key_id). Not the raw provider objects, and never the secret value"
  value = {
    for k, s in local.all_secrets : k => {
      id                     = s.id
      secret_name            = s.secret_name
      current_version_number = s.current_version_number
      rotation_status        = s.rotation_status
      state                  = s.state
      vault_id               = s.vault_id
      key_id                 = s.key_id
    }
  }
}
