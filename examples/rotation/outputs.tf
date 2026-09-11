output "secret_id" {
  description = "OCID of the rotated secret"
  value       = module.secret.secret_ids["ex-rotation-adb-wallet-password"]
}

output "rotation_status" {
  description = "Rotation status reported by the secret"
  value       = module.secret.secrets["ex-rotation-adb-wallet-password"].rotation_status
}
