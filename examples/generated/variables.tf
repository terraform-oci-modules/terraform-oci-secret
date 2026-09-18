variable "compartment_id" {
  description = "The OCID of the compartment to create the secrets in"
  type        = string
}

variable "vault_id" {
  description = "OCID of the vault to create the secrets in (from terraform-oci-vault)"
  type        = string
}

variable "key_id" {
  description = "OCID of a symmetric key in the vault, used to encrypt the secrets"
  type        = string
}
