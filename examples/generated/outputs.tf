output "secret_ids" {
  description = "Map of secret name => OCID"
  value       = module.secret.secret_ids
}
