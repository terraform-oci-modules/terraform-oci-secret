# Generated secrets

Configuration in this directory creates three secrets whose values OCI generates
server-side: a passphrase, an SSH key pair, and 32 random bytes. No secret
material passes through Terraform or lands in state.

## Usage

```bash
$ terraform init
$ terraform plan
$ terraform apply
```

Set `TF_VAR_compartment_id`, `TF_VAR_vault_id`, and `TF_VAR_key_id`. Vault and key
come from a `terraform-oci-vault` deployment.

> **Teardown is not immediate.** `terraform destroy` *schedules* each secret for
> deletion (7-day minimum, no override).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7 |
| <a name="requirement_oci"></a> [oci](#requirement\_oci) | >= 6.26.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_secret"></a> [secret](#module\_secret) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_compartment_id"></a> [compartment\_id](#input\_compartment\_id) | The OCID of the compartment to create the secrets in | `string` | n/a | yes |
| <a name="input_key_id"></a> [key\_id](#input\_key\_id) | OCID of a symmetric key in the vault, used to encrypt the secrets | `string` | n/a | yes |
| <a name="input_vault_id"></a> [vault\_id](#input\_vault\_id) | OCID of the vault to create the secrets in (from terraform-oci-vault) | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_secret_ids"></a> [secret\_ids](#output\_secret\_ids) | Map of secret name => OCID |
<!-- END_TF_DOCS -->
