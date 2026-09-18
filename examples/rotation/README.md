# Rotated secret

Configuration in this directory creates a secret whose value OCI rotates against
an Autonomous Database on a 60-day schedule. Because the secret has a `rotation`
config, the module seeds `content` once and then ignores `secret_content`.

Needs a real ADB OCID, so this example is exercised with `terraform plan` only.

## Usage

```bash
$ terraform init
$ terraform plan
```

Set `TF_VAR_compartment_id`, `TF_VAR_vault_id`, `TF_VAR_key_id`, and
`TF_VAR_adb_id`.

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
| <a name="input_adb_id"></a> [adb\_id](#input\_adb\_id) | OCID of the Autonomous Database whose password this secret holds and rotates | `string` | `"ocid1.autonomousdatabase.oc1..aaaaaaaaexampleadb"` | no |
| <a name="input_compartment_id"></a> [compartment\_id](#input\_compartment\_id) | The OCID of the compartment to create the secret in | `string` | n/a | yes |
| <a name="input_key_id"></a> [key\_id](#input\_key\_id) | OCID of a symmetric key in the vault, used to encrypt the secret | `string` | n/a | yes |
| <a name="input_vault_id"></a> [vault\_id](#input\_vault\_id) | OCID of the vault to create the secret in (from terraform-oci-vault) | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_rotation_status"></a> [rotation\_status](#output\_rotation\_status) | Rotation status reported by the secret |
| <a name="output_secret_id"></a> [secret\_id](#output\_secret\_id) | OCID of the rotated secret |
<!-- END_TF_DOCS -->
