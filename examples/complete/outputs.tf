output "secret_ids" {
  description = "Map of secret name => OCID"
  value       = module.secret.secret_ids
}

output "secrets" {
  description = "Curated attributes of each created secret (no values)"
  value       = module.secret.secrets
}
