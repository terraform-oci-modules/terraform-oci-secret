# OCI Vault Secret Terraform Module

Terraform module which creates **Vault Secrets** on Oracle Cloud Infrastructure
(OCI): `oci_vault_secret` resources inside a vault you pass in, as a map.

Designed to be familiar to users of the [terraform-aws-modules/secrets-manager/aws](https://github.com/terraform-aws-modules/terraform-aws-secrets-manager)
module, mapped to the primitives OCI actually has. AWS Secrets Manager and OCI
Vault secrets differ: an OCI secret must live in a **vault** and name a **key**
in that vault, access is IAM policy (there is no resource policy), rotation is
built in for two target types only, and OCI can generate the value itself. See
[docs/feature_parity.md](docs/feature_parity.md) for the full mapping and design
rationale.

The vault and key come from the separate
[`terraform-oci-vault`](https://github.com/terraform-oci-modules/terraform-oci-vault)
module.

## Usage

```hcl
module "vault" {
  source  = "terraform-oci-modules/vault/oci"
  version = "~> 0.1"

  compartment_id = var.compartment_id
  vault          = { display_name = "platform" }
  keys           = { secrets = { key_shape = { algorithm = "AES", length = 32 } } }
}

module "secret" {
  source  = "terraform-oci-modules/secret/oci"
  version = "~> 0.1"

  compartment_id = var.compartment_id
  vault_id       = module.vault.vault_id
  key_id         = module.vault.key_ids["secrets"]

  secrets = {
    # A value you already have, seeded from Terraform (lands in state).
    db-password = {
      description = "Application database password"
      content     = var.db_password
    }

    # A value OCI generates - never passes through Terraform.
    service-token = {
      description = "Generated service token"
      generation = {
        generation_type     = "PASSPHRASE"
        generation_template = "SECRETS_DEFAULT_PASSWORD"
        passphrase_length   = 32
      }
    }
  }

  tags = { Terraform = "true" }
}
```

## Secret values: `content` vs `generation`

Each secret must set exactly one:

| | `content` | `generation` |
| --- | --- | --- |
| Value comes from | you (a variable, a literal) | OCI, server-side |
| In Terraform state? | **yes** - the OCI provider has no write-only argument (the module marks it `sensitive()` so it is redacted in plan output, but it is still in state) | no |
| Use when | you must seed a known value (vendor API key, existing password) | anything that just needs to be strong and secret |

`generation` maps to `secret_generation_context`. `generation_template` must
match `generation_type`:

| `generation_type` | valid `generation_template` values                  |
| ------------------ | --------------------------------------------------- |
| `PASSPHRASE`        | `SECRETS_DEFAULT_PASSWORD`, `DBAAS_DEFAULT_PASSWORD` |
| `SSH_KEY`           | `RSA_2048`, `RSA_3072`, `RSA_4096`                   |
| `BYTES`             | `BYTES_512`, `BYTES_1024`                            |

**The map key is the secret's identity.** `secret_name`, `vault_id`, and `key_id`
are all immutable - renaming a `secrets` entry (or changing its `key_id`)
destroys the old secret and creates a new one, and the old one then sits in
`PENDING_DELETION` for 7 to 30 days. Rename deliberately.

`ignore_content_changes` (module-wide) stops Terraform reconciling
`secret_content` after creation, for values rotated out of band. Secrets that set
`rotation` are treated this way automatically.

## Rotation

OCI rotation is built in and targets **Autonomous Database** or an **OCI
Function** only - there is no arbitrary rotation function like AWS Lambda.

```hcl
secrets = {
  adb-admin = {
    content = "seed-value"
    rotation = {
      target_system_type            = "ADB"
      adb_id                        = var.adb_id
      rotation_interval             = "P60D"   # ISO 8601, P1D to P360D
      is_scheduled_rotation_enabled = true
    }
  }
}
```

Anything else is rotated by updating the secret content yourself;
`ignore_content_changes` (or the automatic behaviour for `rotation` secrets)
keeps Terraform from fighting it.

## Secret rules

`expiry_rule` and `reuse_rule` map to OCI `secret_rules`:

```hcl
secrets = {
  short-lived = {
    content = "..."
    expiry_rule = {
      version_expiry_interval           = "P7D"   # ISO 8601, P1D to P90D
      block_content_retrieval_on_expiry = true
    }
    reuse_rule = {
      enforce_on_deleted_versions = true
    }
  }
}
```

Use `expiry_rule.time_of_absolute_expiry` (RFC 3339) instead of
`version_expiry_interval` for a fixed expiry date.

## Scheduled deletion

OCI has no immediate delete for a secret. `terraform destroy` calls
`ScheduleSecretDeletion`; the secret moves to `PENDING_DELETION` for a service-set
window (7 to 30 days, defaults to 30) and is only removed then. Unlike
`oci_kms_key`, the OCI provider does not expose `time_of_deletion` on this
resource, so there is **no knob** to shorten the window and no force-delete. This
is why the test suite is mock-only - see [docs/testing.md](docs/testing.md).

## Access control is IAM

An OCI secret has no attached policy. Grant access with an IAM policy statement
(via [`terraform-oci-iam`](https://github.com/terraform-oci-modules/terraform-oci-iam)
or by hand) in the secret's compartment:

```
Allow group app to read secret-bundles in compartment app
Allow dynamic-group app-instances to read secret-bundles in compartment app where target.secret.name = 'db-password'
```

`read secret-bundles` retrieves the value; `use secret-family` / `manage
secret-family` manage the secret. This module creates the secret and exports its
OCID; granting access is a statement elsewhere.

## Replication

`secrets[*].replication` maps to `replication_config`. OCI needs a
`target_vault_id` and `target_key_id` in each destination region (stand those up
with another `terraform-oci-vault` call there):

```hcl
replication = {
  targets = [{
    target_region   = "us-phoenix-1"
    target_vault_id = module.vault_phx.vault_id
    target_key_id   = module.vault_phx.key_ids["secrets"]
  }]
}
```

## Tags

| Variable       | OCI tag type    |
| -------------- | --------------- |
| `tags`         | `freeform_tags` |
| `defined_tags` | `defined_tags`  |

Every `secrets` entry accepts its own `tags` / `defined_tags` that merge over the
module-wide values. Tags are applied at create time and later changes are ignored
(`lifecycle { ignore_changes = [defined_tags, freeform_tags] }`), matching the
sibling OCI modules.

## What this module does not do

Out of scope: creating the vault or key (that is `terraform-oci-vault`), reading
secret values back (`oci_secrets_secretbundle`), and replica-secret write
forwarding. Not applicable: resource policies (access is IAM), write-only secret
arguments (the OCI provider has none), and `recovery_window_in_days` (no knob).
See [docs/feature_parity.md](docs/feature_parity.md).

## Examples

- [simple](examples/simple) - One secret with a literal `content`
- [complete](examples/complete) - Literal, generated, expiring, and function-rotated secrets in one call
- [generated](examples/generated) - `PASSPHRASE`, `SSH_KEY`, and `BYTES` secrets OCI generates - nothing sensitive in Terraform
- [rotation](examples/rotation) - A secret rotated against an Autonomous Database on a schedule (`plan`-only)

## Wrappers

- [wrappers](wrappers) - Terragrunt-style `for_each` wrapper for the root module

## Testing

The whole suite runs against a mocked OCI provider (`terraform test`) - no
credentials, no real resources, no cost. Secret deletion is always scheduled days
out with no override, so real apply/destroy tests cannot clean up. See
[docs/testing.md](docs/testing.md).

## AWS to OCI feature parity

See [docs/feature_parity.md](docs/feature_parity.md) for the full comparison
against `terraform-aws-modules/secrets-manager/aws`.

## Related Projects

### Official Oracle module

Oracle maintains official Vault building blocks under
[oracle-terraform-modules](https://github.com/oracle-terraform-modules).

**When to use this module:**
- You are migrating from AWS and want the same module layout and interface as `terraform-aws-modules/secrets-manager/aws`
- You want a consistent interface across AWS and OCI infrastructure

### Disclaimer

This is an independent community module and is **not affiliated with, endorsed by, or supported by Oracle Corporation**. Oracle Cloud Infrastructure (OCI) is a trademark of Oracle Corporation. This module uses the publicly available [OCI Terraform provider](https://registry.terraform.io/providers/oracle/oci/latest) under its Mozilla Public License 2.0.

## License

[Apache 2.0](LICENSE)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7 |
| <a name="requirement_oci"></a> [oci](#requirement\_oci) | >= 6.26.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_oci"></a> [oci](#provider\_oci) | >= 6.26.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [oci_vault_secret.ignore_content](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/vault_secret) | resource |
| [oci_vault_secret.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/vault_secret) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_compartment_id"></a> [compartment\_id](#input\_compartment\_id) | The OCID of the compartment that holds the secrets | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Controls if resources should be created (master switch - affects all resources) | `bool` | `true` | no |
| <a name="input_defined_tags"></a> [defined\_tags](#input\_defined\_tags) | A map of defined tags (namespace.key = value) to add to every secret. Applied at create time only (changes are ignored, matching the sibling OCI modules) | `map(string)` | `{}` | no |
| <a name="input_ignore_content_changes"></a> [ignore\_content\_changes](#input\_ignore\_content\_changes) | When true, Terraform stops reconciling `secret_content` for every secret<br/>after creation (drift from out-of-band updates or rotation is ignored).<br/>Changing this after creation is a destructive operation (the secrets are<br/>replaced). Secrets that set `rotation` are always treated this way<br/>regardless of this flag. | `bool` | `false` | no |
| <a name="input_key_id"></a> [key\_id](#input\_key\_id) | Default OCID of the symmetric master encryption key used to encrypt the<br/>secrets. Must be a key in `vault_id`. Override per secret with<br/>`secrets[*].key_id`. Required unless every secret sets its own key\_id. | `string` | `null` | no |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | Map of secrets to create in the vault, keyed by name (the OCI `secret_name`).<br/><br/>Per entry:<br/>  key\_id       : symmetric key OCID for this secret (defaults to var.key\_id).<br/>  description  : brief description.<br/>  metadata     : admin key-value context (connection strings, endpoints, ...).<br/>  content      : literal secret value. The module base64-encodes it and marks<br/>                 it sensitive so it is redacted in plan output. NOTE: the<br/>                 value is still stored in Terraform state - the OCI provider<br/>                 has no write-only argument. Mutually exclusive with<br/>                 `generation`.<br/>  generation   : have OCI generate the value instead of passing `content`:<br/>                   generation\_type     : PASSPHRASE \| SSH\_KEY \| BYTES<br/>                   generation\_template : must match generation\_type -<br/>                                         PASSPHRASE: SECRETS\_DEFAULT\_PASSWORD,<br/>                                         DBAAS\_DEFAULT\_PASSWORD<br/>                                         SSH\_KEY: RSA\_2048, RSA\_3072, RSA\_4096<br/>                                         BYTES: BYTES\_512, BYTES\_1024<br/>                   passphrase\_length   : PASSPHRASE only<br/>                   secret\_template     : optional structure to embed the value in<br/>  rotation     : built-in rotation (ADB / FUNCTION targets only):<br/>                   target\_system\_type            : ADB \| FUNCTION<br/>                   adb\_id / function\_id          : the target OCID<br/>                   rotation\_interval             : ISO 8601, P1D to P360D<br/>                   is\_scheduled\_rotation\_enabled : turn the schedule on<br/>  expiry\_rule  : version\_expiry\_interval (ISO 8601, P1D to P90D) OR<br/>                 time\_of\_absolute\_expiry (RFC 3339); block\_content\_retrieval\_on\_expiry.<br/>  reuse\_rule   : enforce\_on\_deleted\_versions - forbid reusing previous content.<br/>  replication  : cross-region replica config (needs a target vault + key per region):<br/>                   is\_write\_forward\_enabled<br/>                   targets : list of { target\_region, target\_key\_id, target\_vault\_id }<br/>  timeouts     : create / update / delete timeout overrides.<br/>  tags / defined\_tags : per-secret tags, merged over var.tags / var.defined\_tags. | <pre>map(object({<br/>    key_id      = optional(string)<br/>    description = optional(string)<br/>    metadata    = optional(map(string))<br/>    content     = optional(string)<br/>    generation = optional(object({<br/>      generation_type     = string<br/>      generation_template = string<br/>      passphrase_length   = optional(number)<br/>      secret_template     = optional(string)<br/>    }))<br/>    rotation = optional(object({<br/>      target_system_type            = string<br/>      adb_id                        = optional(string)<br/>      function_id                   = optional(string)<br/>      rotation_interval             = optional(string)<br/>      is_scheduled_rotation_enabled = optional(bool)<br/>    }))<br/>    expiry_rule = optional(object({<br/>      version_expiry_interval           = optional(string)<br/>      time_of_absolute_expiry           = optional(string)<br/>      block_content_retrieval_on_expiry = optional(bool)<br/>    }))<br/>    reuse_rule = optional(object({<br/>      enforce_on_deleted_versions = optional(bool)<br/>    }))<br/>    replication = optional(object({<br/>      is_write_forward_enabled = optional(bool)<br/>      targets = list(object({<br/>        target_region   = string<br/>        target_key_id   = string<br/>        target_vault_id = string<br/>      }))<br/>    }))<br/>    timeouts = optional(object({<br/>      create = optional(string)<br/>      update = optional(string)<br/>      delete = optional(string)<br/>    }))<br/>    tags         = optional(map(string), {})<br/>    defined_tags = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of freeform tags to add to every secret. Applied at create time only (changes are ignored, matching the sibling OCI modules) | `map(string)` | `{}` | no |
| <a name="input_vault_id"></a> [vault\_id](#input\_vault\_id) | OCID of the vault the secrets are created in. From terraform-oci-vault: module.vault.vault\_id | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_secret_ids"></a> [secret\_ids](#output\_secret\_ids) | Map of secret name => secret OCID |
| <a name="output_secrets"></a> [secrets](#output\_secrets) | Map of secret name => curated attributes (id, secret\_name, current\_version\_number, rotation\_status, state, vault\_id, key\_id). Not the raw provider objects, and never the secret value |
<!-- END_TF_DOCS -->
