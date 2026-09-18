variable "compartment_id" {
  description = "The OCID of the compartment to create the secret in"
  type        = string
}

variable "vault_id" {
  description = "OCID of the vault to create the secret in (from terraform-oci-vault)"
  type        = string
}

variable "key_id" {
  description = "OCID of a symmetric key in the vault, used to encrypt the secret"
  type        = string
}

variable "adb_id" {
  description = "OCID of the Autonomous Database whose password this secret holds and rotates"
  type        = string
  default     = "ocid1.autonomousdatabase.oc1..aaaaaaaaexampleadb"
}
