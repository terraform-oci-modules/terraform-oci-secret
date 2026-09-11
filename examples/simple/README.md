# Simple secret

Configuration in this directory creates one secret with a literal value in an
existing vault.

## Usage

```bash
$ terraform init
$ terraform plan
$ terraform apply
```

Set `TF_VAR_compartment_id`, `TF_VAR_vault_id`, and `TF_VAR_key_id` (a symmetric
key in that vault). Both come from a `terraform-oci-vault` deployment.

> The literal `content` is stored in Terraform state - the OCI provider has no
> write-only argument for secret content. For values that do not need external
> seeding, prefer the `generated` example.

> **Teardown is not immediate.** `terraform destroy` *schedules* the secret for
> deletion (7-day minimum, no override); it sits in `PENDING_DELETION` until then.

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
| <a name="input_compartment_id"></a> [compartment\_id](#input\_compartment\_id) | The OCID of the compartment to create the secret in | `string` | n/a | yes |
| <a name="input_key_id"></a> [key\_id](#input\_key\_id) | OCID of a symmetric key in the vault, used to encrypt the secret | `string` | n/a | yes |
| <a name="input_vault_id"></a> [vault\_id](#input\_vault\_id) | OCID of the vault to create the secret in (from terraform-oci-vault) | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_secret"></a> [secret](#output\_secret) | Curated attributes of the created secret (no value) |
| <a name="output_secret_id"></a> [secret\_id](#output\_secret\_id) | OCID of the created secret |
<!-- END_TF_DOCS -->
