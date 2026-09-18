# Testing

The whole suite runs against a **mocked OCI provider** - no credentials, no real
resources, no cost, safe to run anytime. This is deliberate: OCI secret deletion
is always scheduled days out (7 to 30, no `time_of_deletion` knob on this
resource, no force-delete), so real apply/destroy tests cannot clean up after
themselves. The module is exercised with `mock_provider "oci" {}` instead.

```bash
terraform init
terraform test
```

## What is covered

| File                          | Against            | Checks                                                                 |
| ----------------------------- | ------------------ | --------------------------------------------------------------------- |
| `tests/unit_mappings.tftest.hcl` | the module root    | content vs generation, base64 encoding, the managed vs ignore-content split (rotation and the module flag), `key_id` fallback, `secret_rules` mapping, tag merge, `create = false`, and a reject case for every `validation` rule plus the missing-key precondition |
| `tests/simple.tftest.hcl`        | `examples/simple`  | one literal secret plans and exposes its outputs                      |
| `tests/complete.tftest.hcl`      | `examples/complete` | four secrets across the managed and ignore-content resources         |
| `tests/generated.tftest.hcl`     | `examples/generated` | three server-generated secrets                                       |
| `tests/rotation.tftest.hcl`      | `examples/rotation` | an ADB-rotated secret plans through the ignore-content path          |

## Running a real apply by hand

Apply an example directly (not through `terraform test`):

```bash
cd examples/simple
export TF_VAR_compartment_id="ocid1.compartment.oc1..aaaa"
export TF_VAR_vault_id="ocid1.vault.oc1.iad.aaaa"
export TF_VAR_key_id="ocid1.key.oc1.iad.aaaa"
terraform init && terraform apply
# ... inspect ...
terraform destroy
```

`terraform destroy` schedules each secret for deletion 30 days out (7-day
minimum, not adjustable through Terraform). Cancel or reschedule with `oci vault
secret schedule-secret-deletion` / `cancel-secret-deletion`, or leave it - a
`PENDING_DELETION` secret costs nothing and does not block re-creating one with
the same name.

## Notes

- `vault_id` and `key_id` must be real for a live apply: the key must be a
  **symmetric** key **in that vault**.
- `secrets[*].content` is stored (base64-encoded) in Terraform state. The OCI
  provider has no write-only argument for it. Use `secrets[*].generation` to keep
  values out of state entirely.
- A secret with `rotation` is created through the ignore-content resource, so
  `terraform plan` will not show drift after OCI rotates the value.
- `generation.generation_template` must be one of a fixed set per
  `generation_type` (see the README table) - there is no free-form template name.
  This module's mock suite cannot catch a wrong-but-plausible-looking template
  name; only a real apply does. A live apply/destroy of a literal secret, a
  generated `PASSPHRASE` secret, and three key types was run against a real
  tenancy on 2026-09-18 and completed cleanly end to end.
