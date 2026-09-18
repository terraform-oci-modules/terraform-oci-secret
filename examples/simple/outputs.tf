output "secret_id" {
  description = "OCID of the created secret"
  value       = module.secret.secret_ids["ex-simple-db-password"]
}

output "secret" {
  description = "Curated attributes of the created secret (no value)"
  value       = module.secret.secrets["ex-simple-db-password"]
}
