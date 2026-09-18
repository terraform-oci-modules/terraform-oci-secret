# Secrets Manager (AWS) to Vault Secret (OCI) feature parity

Comparison against [`terraform-aws-modules/secrets-manager`](https://github.com/terraform-aws-modules/terraform-aws-secrets-manager)
v2.1.0. That module manages **one** secret: the secret container, one secret
version (its value), an optional resource policy, and optional Lambda-driven
rotation. This module manages a **map** of `oci_vault_secret` resources inside a
vault you pass in.

It is not a 1:1 mapping. AWS Secrets Manager and OCI Vault secrets differ:

- An AWS secret is self-contained and encrypted with an AWS-managed or
  customer KMS key by reference. An OCI secret **must live in a Vault** and
  **must name a symmetric KMS key in that vault**. So this module takes a
  `vault_id` and a `key_id` (both from
  [`terraform-oci-vault`](https://github.com/terraform-oci-modules/terraform-oci-vault))
  as required inputs; it never creates a vault or a key.
- AWS models the value as a separate `aws_secretsmanager_secret_version`
  resource with staging labels (`AWSCURRENT`, `AWSPREVIOUS`, ...). OCI folds the
  value into the secret resource as a `secret_content` block; version history and
  staging are managed by the service, not as Terraform resources. This module
  always writes the value as the current version.
- AWS controls access with a **resource policy** on the secret. OCI controls it
  with **IAM policy statements** in the compartment
  (`Allow group app to read secret-family in compartment app`). The whole AWS
  `create_policy` / `policy_statements` surface has no home here: it belongs in
  [`terraform-oci-iam`](https://github.com/terraform-oci-modules/terraform-oci-iam).
- AWS rotation runs a **Lambda function** you write. OCI rotation is **built in**
  for two target types only (Autonomous Database, OCI Functions) plus a schedule;
  there is no "bring your own rotation function" for arbitrary targets.
- OCI can **generate** the secret value itself (`secret_generation_context`):
  passphrases, SSH keys, byte strings. AWS approximates this with an ephemeral
  `random_password`. Generation is the path that keeps secret material out of
  Terraform state entirely, and this module leads with it.

Gaps are split three ways:

- [Not applicable](#not-applicable-to-oci): no OCI equivalent, or the concept is
  expressed through a different service.
- [Out of scope](#out-of-scope): OCI supports it, this module deliberately does not.
- [Not yet implemented](#not-yet-implemented): the backlog.

Status values: `mapped` where the concept carries over, `n/a` where no OCI
equivalent exists at the secret level, `OCI-only` for features with no AWS
counterpart, `backlog` for provider-supported features this module does not
expose yet.

## Feature mapping

### Core / control

| Feature             | AWS                        | OCI                                        | Status   |
| ------------------- | -------------------------- | ------------------------------------------ | -------- |
| Create toggle       | `create`                   | `create`                                   | mapped   |
| Target compartment  | AWS account (implicit)     | `compartment_id` (required)                | mapped   |
| Target vault        | none                       | `vault_id` (required)                       | OCI-only |
| Encryption key      | `kms_key_id` (optional, defaults to `aws/secretsmanager`) | `key_id` (**required**, per module or per secret) | mapped (required) |
| Per-resource region | `region`                   | none (provider carries the region)         | n/a      |
| Freeform tags       | `tags`                     | `tags` + per-secret `tags`                  | mapped   |
| Defined tags        | none                       | `defined_tags` + per-secret `defined_tags`  | OCI-only |
| One secret vs many  | one secret per module call | `secrets` (map, name = key)                 | mapped (one to many) |

> **`vault_id` + `key_id` are required.** An OCI secret cannot exist outside a
> vault and cannot be created without naming a symmetric key **in that vault**.
> Both come from `terraform-oci-vault`: `module.vault.vault_id` and
> `module.vault.key_ids["<name>"]`. `key_id` can be set once at the module level
> and overridden per secret.

### Secret container

AWS resource: `aws_secretsmanager_secret`.

| Feature                     | AWS                              | OCI                                   | Status   |
| --------------------------- | -------------------------------- | ------------------------------------- | -------- |
| Name                        | `name` / `name_prefix`           | `secrets` map key (= `secret_name`)   | mapped   |
| Description                 | `description`                    | `secrets[*].description`              | mapped   |
| Admin metadata              | none                             | `secrets[*].metadata` (map)           | OCI-only |
| Recovery window             | `recovery_window_in_days` (0, or 7-30) | none (see note)                 | n/a      |
| Cross-region replication    | `replica` (map of region => kms key) | `secrets[*].replication` (list of {region, key_id, vault_id}) | mapped (needs a target vault) |
| Force-overwrite replica     | `force_overwrite_replica_secret` | none                                  | n/a      |
| Delete timeout override     | none                             | `secrets[*].timeouts`                 | OCI-only |

> **No `recovery_window_in_days`.** AWS lets you pick 7-30 days, or `0` to force
> immediate deletion. OCI has neither: `terraform destroy` calls
> `ScheduleSecretDeletion`, the secret goes to `PENDING_DELETION` for a
> service-set window (7-30 days, defaults to 30), and the OCI provider does not
> expose `time_of_deletion` on this resource (unlike `oci_kms_key`), so there is
> no knob at all. There is no force-delete. Documented in `docs/testing.md`; this
> is why the test suite is mock-only.
>
> **Replication needs a target vault.** AWS replication just needs a region (and
> optionally a KMS key). OCI needs a `target_vault_id` and `target_key_id` in the
> destination region for every target - you must stand those up first (another
> `terraform-oci-vault` call in that region). `replication` is therefore an
> advanced, mostly-`plan`-tested feature.

### Secret value

AWS resource: `aws_secretsmanager_secret_version` (plus an `ignore_changes`
variant and an `ephemeral.random_password`). OCI: the `secret_content` or
`secret_generation_context` block on the secret itself.

| Feature                       | AWS                                    | OCI                                          | Status   |
| ----------------------------- | -------------------------------------- | ------------------------------------------- | -------- |
| Set a string value            | `secret_string`                        | `secrets[*].content` (module base64-encodes it) | mapped |
| Set a binary value            | `secret_binary` (base64)               | `secrets[*].content` + `content_type` (backlog) | backlog |
| Write-only value (not in state) | `secret_string_wo` (1.11+, ephemeral) | none (the OCI provider has no write-only arg) | n/a    |
| Generate a value              | `create_random_password` + `ephemeral.random_password` | `secrets[*].generation` (`secret_generation_context`) | mapped (richer) |
| Random password length / chars | `random_password_length`, `random_password_override_special` | `generation.passphrase_length`, `generation.secret_template` | mapped |
| Staging labels                | `version_stages`                       | none - the module always writes the current version | backlog (`stage = PENDING`) |
| Ignore external value changes | `ignore_secret_changes`                | `secrets[*].ignore_content_changes`         | mapped   |
| Version identifier output     | `secret_version_id`                    | `current_version_number` (curated output)   | mapped   |

> **`content` lands in state.** The OCI provider exposes no write-only argument
> for `secret_content.content`, and does not even mark it sensitive. The module
> wraps it with `sensitive()` so it is redacted in `terraform plan` output, but
> any value passed through `secrets[*].content` is still stored (base64-encoded)
> in the Terraform state, the same as AWS `secret_string`. Mark the state backend
> accordingly.
>
> **Prefer `generation`.** `secrets[*].generation` maps to
> `secret_generation_context`: OCI generates the value (a passphrase, an SSH key
> pair, N random bytes) and it is never sent through Terraform. This is the
> recommended path for anything that does not have to be seeded from an external
> value. `generation_type` is `PASSPHRASE`, `SSH_KEY`, or `BYTES`, and
> `generation_template` must be one of that type's fixed OCI template names
> (`SECRETS_DEFAULT_PASSWORD`/`DBAAS_DEFAULT_PASSWORD` for `PASSPHRASE`,
> `RSA_2048`/`RSA_3072`/`RSA_4096` for `SSH_KEY`, `BYTES_512`/`BYTES_1024` for
> `BYTES`) - there is no free-form template name, and the module validates the
> pairing.
>
> **No `stage`.** OCI's `secret_content.stage` lets an update push a value as
> `PENDING` (staged, not yet active) for later promotion, but only `CURRENT` is
> valid on create. Since this module has one `secret_content` block per secret,
> exposing `stage` would only enable an awkward half-workflow, so it always
> writes `CURRENT`. Staged rotation is a backlog item.

### Rotation

AWS resource: `aws_secretsmanager_secret_rotation` (a Lambda ARN + rules). OCI:
the `rotation_config` block.

| Feature                    | AWS                                   | OCI                                          | Status   |
| -------------------------- | ------------------------------------- | ------------------------------------------- | -------- |
| Enable rotation            | `enable_rotation`                     | `secrets[*].rotation` (presence of the object) | mapped |
| Rotation function          | `rotation_lambda_arn` (any Lambda)    | `rotation.target_system_type` (`ADB` or `FUNCTION` only) + `adb_id` / `function_id` | mapped (fixed target types) |
| Schedule                   | `rotation_rules.automatically_after_days` / `schedule_expression` | `rotation.rotation_interval` (ISO 8601, `P1D`-`P360D`) + `rotation.is_scheduled_rotation_enabled` | mapped (ISO 8601) |
| Rotate now                 | `rotate_immediately`                  | none (no immediate-rotate arg)              | n/a      |
| Rotation duration window   | `rotation_rules.duration`             | none                                        | n/a      |

> **OCI rotation is built in, for two targets.** There is no arbitrary rotation
> function. If the secret backs an Autonomous Database or you have written an OCI
> Function that follows the rotation contract, OCI drives the rotation on the
> `rotation_interval` schedule. Anything else is rotated out of band (update the
> secret content yourself) and `ignore_content_changes` keeps Terraform from
> fighting it.

### Secret rules

No AWS counterpart. OCI `secret_rules` control expiry and reuse.

| Feature                        | AWS  | OCI                                            | Status   |
| ------------------------------ | ---- | --------------------------------------------- | -------- |
| Version expiry interval        | none | `secrets[*].expiry_rule.version_expiry_interval` (`P1D`-`P90D`) | OCI-only |
| Absolute expiry time           | none | `secrets[*].expiry_rule.time_of_absolute_expiry` (RFC 3339) | OCI-only |
| Block read after expiry        | none | `secrets[*].expiry_rule.block_content_retrieval_on_expiry` | OCI-only |
| Content-reuse rule             | none | `secrets[*].reuse_rule.enforce_on_deleted_versions` | OCI-only |

### Access control

| Feature              | AWS                          | OCI                                  | Status |
| -------------------- | ---------------------------- | ------------------------------------ | ------ |
| Resource policy      | `create_policy`, `policy_statements`, `source_policy_documents`, `override_policy_documents` | IAM policy in `terraform-oci-iam` | n/a |
| Block public policy  | `block_public_policy`        | none (no resource policy to block)   | n/a    |

> **All of this is IAM.** To let a principal read a secret on OCI:
> `Allow group app to read secret-bundles in compartment app` (read the value) or
> `... to use secret-family ...` (manage). The module creates the secret and
> exports its OCID; granting access is a statement in `terraform-oci-iam`. The
> README shows the common statements.

### Submodules and wrappers

| AWS                     | OCI                                   | Status   |
| ----------------------- | ------------------------------------- | -------- |
| root module (one secret) | root module (`secrets` map)          | mapped   |
| `wrappers/`             | `wrappers/`                           | mapped   |

## Variable mapping

Equivalent concept, different name. Anything not listed maps by an identical name.

| AWS                          | OCI                              | Notes                                                         |
| ---------------------------- | -------------------------------- | ----------------------------------------------------------- |
| `create`                     | `create`                         | master toggle                                                |
| `region`                     | none                             | provider carries the region                                  |
| `name` + one call per secret | `secrets` (map)                   | one module call manages many secrets, keyed by name          |
| `kms_key_id`                 | `key_id` + `secrets[*].key_id`    | required on OCI; the key must be in `vault_id`               |
| `description`                | `secrets[*].description`          |                                                              |
| `secret_string`              | `secrets[*].content`             | module base64-encodes; lands in state either way             |
| `secret_binary`              | `secrets[*].content` (backlog)   | binary content type not exposed yet                          |
| `secret_string_wo`           | none                             | no write-only arg in the OCI provider                        |
| `create_random_password`, `random_password_*` | `secrets[*].generation` | OCI generates the value server-side                     |
| `ignore_secret_changes`      | `secrets[*].ignore_content_changes` |                                                          |
| `version_stages`             | none                            | the module always writes the current version                 |
| `recovery_window_in_days`    | none                             | scheduled deletion is fixed service behaviour, no knob       |
| `replica`                    | `secrets[*].replication`         | OCI needs a target vault + key per region, not just a region |
| `enable_rotation`, `rotation_lambda_arn`, `rotation_rules` | `secrets[*].rotation` | ADB / FUNCTION targets only; ISO 8601 interval        |
| `create_policy`, `policy_statements`, `block_public_policy` | none | secret access is IAM policy (`terraform-oci-iam`)      |

OCI-only variables, no AWS counterpart:

| OCI variable                          | What it does                                                        |
| ------------------------------------- | ------------------------------------------------------------------ |
| `vault_id`                            | the vault every secret is created in (required)                    |
| `key_id`                              | default encryption key for the secrets (required, per module or per secret) |
| `secrets[*].metadata`                 | admin key-value context (connection strings, endpoints, ...)       |
| `secrets[*].generation`               | server-side value generation (passphrase / SSH key / bytes)        |
| `secrets[*].expiry_rule`              | version expiry interval or absolute expiry, block-read-on-expiry   |
| `secrets[*].reuse_rule`               | forbid reusing previous content                                    |
| `secrets[*].timeouts`                 | create / update / delete timeout overrides                         |
| `defined_tags` everywhere             | OCI's tag-namespace system alongside freeform `tags`               |

## Output mapping

| AWS                        | OCI                                     | Notes                                          |
| -------------------------- | --------------------------------------- | --------------------------------------------- |
| `secret_id`                | `secret_ids` (map name to OCID)         | one secret on AWS, a map here                  |
| `secret_arn`               | `secret_ids`                            | OCID, no ARN                                   |
| `secret_name`              | map keys / `secrets` output             |                                               |
| `secret_string` / `secret_binary` | none                             | the module does not read secret values back    |
| `secret_version_id`        | `secrets[*].current_version_number`     | in the curated `secrets` output               |
| `secret_replica`           | `secrets[*]` (curated)                  | replication status per secret                  |
| (none)                     | `secrets` (curated objects)             | id, secret_name, current_version_number, rotation_status, state, per secret |

Curated outputs mirror the `vault` and `iam` modules: per-name maps of a stable
attribute subset, never the raw provider objects, and **no secret values** (this
module writes secrets, it does not read them back).

## Not applicable to OCI

| AWS feature                                              | Why it does not port                                                              |
| ------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `create_policy`, `policy_statements`, `source_policy_documents`, `override_policy_documents`, `block_public_policy` | OCI secrets have no attached policy. Access is IAM policy statements in the compartment (`terraform-oci-iam`). |
| `secret_string_wo`, `secret_string_wo_version`           | The OCI provider exposes no write-only argument for secret content.            |
| `recovery_window_in_days` (including `0` force-delete)   | OCI scheduled deletion is fixed service behaviour (7-30 days, no `time_of_deletion` on this resource) and there is no force-delete. |
| `rotate_immediately`, `rotation_rules.duration`          | Not exposed by the OCI rotation model.                                        |
| `rotation_lambda_arn` (arbitrary function)              | OCI rotation targets are `ADB` and `FUNCTION` only, following a fixed contract. |
| `force_overwrite_replica_secret`                        | No equivalent in the OCI replication model.                                    |
| `region` / every `*_arn` output                        | OCI uses OCIDs and a provider-bound region.                                    |

## Out of scope

OCI supports these; this module does not (yet, or by design).

- **Reading secret values back.** The `oci_secrets_secretbundle` data source
  retrieves the decrypted value and stores it (sensitive) in state. That is a
  runtime concern, not infrastructure; this module writes secrets and never
  reads them.
- **Replica-secret write forwarding.** The OCI provider blocks update/delete on
  replica secrets outright ("use SDK/CLI/Console"). The module creates the
  replication config on the source secret only.
- **Creating the vault or the key.** That is `terraform-oci-vault`. This module
  requires both OCIDs as input.
- **Vault-wide secret settings.** Anything that is a property of the vault rather
  than a single secret.

## Not yet implemented

| Gap                       | Detail                                                                                                                       | AWS analog                     |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| Staged rotation           | `stage = PENDING` on `secret_content` - stage a new value without promoting it. Needs a two-block or two-version design the current single-content model does not support. | `version_stages` |
| Binary secret content     | `secret_content.content_type` other than `BASE64` text; a `content_base64` input for pre-encoded binary.                      | `secret_binary`                |
| `secret_template`         | The generation template that embeds generated values into a JSON structure (`secret_generation_context.secret_template`).     | (none)                         |
| Multi-target replication   | The module caps `replication` at OCI's default of 3 targets; the override for more is not exposed.                            | `replica` (unbounded)          |
| Manual deletion scheduling | The `ScheduleSecretDeletion` API accepts a `timeOfDeletion`, but the OCI provider does not wire it and `time_of_deletion` is computed-only. Nothing the module can do until the provider changes. | `recovery_window_in_days` |

## Examples

All examples take `vault_id` and `key_id` as inputs rather than composing with
`terraform-oci-vault` (which is a separate, currently private module). The README
shows the composition.

| Example          | What it covers                                                                                                  | AWS counterpart |
| ---------------- | ------------------------------------------------------------------------------------------------------------ | --------------- |
| `simple`         | One secret with a literal `content`                                                                           | (minimal)       |
| `complete`       | Several secrets: one literal, one generated passphrase, one with `metadata` + an `expiry_rule`, one with `ignore_content_changes` module-wide off but per-secret rotation | `complete`      |
| `generated`      | Secrets whose values OCI generates (`PASSPHRASE`, `SSH_KEY`, `BYTES`) - nothing sensitive passes through Terraform | `create_random_password` |
| `rotation`       | A secret with `rotation` pointing at an Autonomous Database, on an ISO 8601 schedule (`plan`-tested; needs a real ADB) | rotation section of `complete` |

## Testing note

Like `terraform-oci-vault`, secret deletion is always **scheduled** (7-30 days,
no `time_of_deletion` knob, no force-delete), so a real apply/destroy test
cannot fully tear down. The suite runs entirely against a **mocked provider**
(`mock_provider "oci" {}`): a unit suite against the module root for input and
mapping logic plus every `validation` block, and one mock test per example.
Running a real apply is a deliberate by-hand step, documented in
`docs/testing.md`. The repo follows `terraform-oci-vault`: kept private and
unreleased for now, with the Release workflow's push trigger removed.
