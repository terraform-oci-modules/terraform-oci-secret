################################################################################
# Core / Control
################################################################################

variable "create" {
  description = "Controls if resources should be created (master switch - affects all resources)"
  type        = bool
  default     = true
}

variable "compartment_id" {
  description = "The OCID of the compartment that holds the secrets"
  type        = string

  validation {
    condition     = can(regex("^ocid1\\.(compartment|tenancy)\\.[a-z0-9.]+", var.compartment_id))
    error_message = "compartment_id must be a valid OCID starting with ocid1.compartment or ocid1.tenancy."
  }
}

variable "vault_id" {
  description = "OCID of the vault the secrets are created in. From terraform-oci-vault: module.vault.vault_id"
  type        = string

  validation {
    condition     = can(regex("^ocid1\\.vault\\.[a-z0-9.-]+", var.vault_id))
    error_message = "vault_id must be a valid vault OCID starting with ocid1.vault."
  }
}

variable "key_id" {
  description = <<-EOT
    Default OCID of the symmetric master encryption key used to encrypt the
    secrets. Must be a key in `vault_id`. Override per secret with
    `secrets[*].key_id`. Required unless every secret sets its own key_id.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.key_id == null ? true : can(regex("^ocid1\\.key\\.[a-z0-9.-]+", var.key_id))
    error_message = "key_id must be a valid key OCID starting with ocid1.key."
  }
}

variable "ignore_content_changes" {
  description = <<-EOT
    When true, Terraform stops reconciling `secret_content` for every secret
    after creation (drift from out-of-band updates or rotation is ignored).
    Changing this after creation is a destructive operation (the secrets are
    replaced). Secrets that set `rotation` are always treated this way
    regardless of this flag.
  EOT
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of freeform tags to add to every secret. Applied at create time only (changes are ignored, matching the sibling OCI modules)"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "defined_tags" {
  description = "A map of defined tags (namespace.key = value) to add to every secret. Applied at create time only (changes are ignored, matching the sibling OCI modules)"
  type        = map(string)
  default     = {}
  nullable    = false
}

################################################################################
# Secrets
################################################################################

variable "secrets" {
  description = <<-EOT
    Map of secrets to create in the vault, keyed by name (the OCI `secret_name`).

    Per entry:
      key_id       : symmetric key OCID for this secret (defaults to var.key_id).
      description  : brief description.
      metadata     : admin key-value context (connection strings, endpoints, ...).
      content      : literal secret value. The module base64-encodes it and marks
                     it sensitive so it is redacted in plan output. NOTE: the
                     value is still stored in Terraform state - the OCI provider
                     has no write-only argument. Mutually exclusive with
                     `generation`.
      generation   : have OCI generate the value instead of passing `content`:
                       generation_type     : PASSPHRASE | SSH_KEY | BYTES
                       generation_template : predefined template name
                       passphrase_length   : PASSPHRASE only
                       secret_template     : optional structure to embed the value in
      rotation     : built-in rotation (ADB / FUNCTION targets only):
                       target_system_type            : ADB | FUNCTION
                       adb_id / function_id          : the target OCID
                       rotation_interval             : ISO 8601, P1D to P360D
                       is_scheduled_rotation_enabled : turn the schedule on
      expiry_rule  : version_expiry_interval (ISO 8601, P1D to P90D) OR
                     time_of_absolute_expiry (RFC 3339); block_content_retrieval_on_expiry.
      reuse_rule   : enforce_on_deleted_versions - forbid reusing previous content.
      replication  : cross-region replica config (needs a target vault + key per region):
                       is_write_forward_enabled
                       targets : list of { target_region, target_key_id, target_vault_id }
      timeouts     : create / update / delete timeout overrides.
      tags / defined_tags : per-secret tags, merged over var.tags / var.defined_tags.
  EOT
  type = map(object({
    key_id      = optional(string)
    description = optional(string)
    metadata    = optional(map(string))
    content     = optional(string)
    generation = optional(object({
      generation_type     = string
      generation_template = string
      passphrase_length   = optional(number)
      secret_template     = optional(string)
    }))
    rotation = optional(object({
      target_system_type            = string
      adb_id                        = optional(string)
      function_id                   = optional(string)
      rotation_interval             = optional(string)
      is_scheduled_rotation_enabled = optional(bool)
    }))
    expiry_rule = optional(object({
      version_expiry_interval           = optional(string)
      time_of_absolute_expiry           = optional(string)
      block_content_retrieval_on_expiry = optional(bool)
    }))
    reuse_rule = optional(object({
      enforce_on_deleted_versions = optional(bool)
    }))
    replication = optional(object({
      is_write_forward_enabled = optional(bool)
      targets = list(object({
        target_region   = string
        target_key_id   = string
        target_vault_id = string
      }))
    }))
    timeouts = optional(object({
      create = optional(string)
      update = optional(string)
      delete = optional(string)
    }))
    tags         = optional(map(string), {})
    defined_tags = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k, v in var.secrets : can(regex("^[A-Za-z0-9._-]{1,255}$", k))])
    error_message = "Each secret name (map key) must be 1-255 characters of letters, digits, dot, underscore, or hyphen."
  }
  validation {
    condition     = alltrue([for k, v in var.secrets : !(v.content != null && v.generation != null)])
    error_message = "secrets[*] cannot set both content and generation."
  }
  validation {
    condition     = alltrue([for k, v in var.secrets : v.content != null || v.generation != null])
    error_message = "secrets[*] must set exactly one of content or generation."
  }
  validation {
    condition = alltrue([
      for k, v in var.secrets :
      v.generation == null || contains(["PASSPHRASE", "SSH_KEY", "BYTES"], v.generation.generation_type)
    ])
    error_message = "secrets[*].generation.generation_type must be PASSPHRASE, SSH_KEY, or BYTES."
  }
  validation {
    condition = alltrue([
      for k, v in var.secrets :
      v.generation == null || v.generation.passphrase_length == null || v.generation.generation_type == "PASSPHRASE"
    ])
    error_message = "secrets[*].generation.passphrase_length is only valid when generation_type is PASSPHRASE."
  }
  validation {
    condition = alltrue([
      for k, v in var.secrets :
      v.rotation == null || contains(["ADB", "FUNCTION"], v.rotation.target_system_type)
    ])
    error_message = "secrets[*].rotation.target_system_type must be ADB or FUNCTION."
  }
  validation {
    condition = alltrue([
      for k, v in var.secrets :
      v.rotation == null || v.rotation.target_system_type != "ADB" || v.rotation.adb_id != null
    ])
    error_message = "secrets[*].rotation with target_system_type = ADB requires adb_id."
  }
  validation {
    condition = alltrue([
      for k, v in var.secrets :
      v.rotation == null || v.rotation.target_system_type != "FUNCTION" || v.rotation.function_id != null
    ])
    error_message = "secrets[*].rotation with target_system_type = FUNCTION requires function_id."
  }
  validation {
    condition = alltrue([
      for k, v in var.secrets :
      v.rotation == null || v.rotation.rotation_interval == null ||
      try(tonumber(regex("^P([0-9]+)D$", v.rotation.rotation_interval)[0]) >= 1 && tonumber(regex("^P([0-9]+)D$", v.rotation.rotation_interval)[0]) <= 360, false)
    ])
    error_message = "secrets[*].rotation.rotation_interval must be an ISO 8601 day duration from P1D to P360D (e.g. P30D)."
  }
  validation {
    condition = alltrue([
      for k, v in var.secrets :
      v.expiry_rule == null || v.expiry_rule.version_expiry_interval == null ||
      try(tonumber(regex("^P([0-9]+)D$", v.expiry_rule.version_expiry_interval)[0]) >= 1 && tonumber(regex("^P([0-9]+)D$", v.expiry_rule.version_expiry_interval)[0]) <= 90, false)
    ])
    error_message = "secrets[*].expiry_rule.version_expiry_interval must be an ISO 8601 day duration from P1D to P90D (e.g. P7D)."
  }
  validation {
    condition = alltrue([
      for k, v in var.secrets :
      v.expiry_rule == null || v.expiry_rule.time_of_absolute_expiry == null ||
      can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$", v.expiry_rule.time_of_absolute_expiry))
    ])
    error_message = "secrets[*].expiry_rule.time_of_absolute_expiry must be an RFC 3339 timestamp."
  }
  validation {
    condition = alltrue([
      for k, v in var.secrets :
      v.expiry_rule == null || !(v.expiry_rule.version_expiry_interval != null && v.expiry_rule.time_of_absolute_expiry != null)
    ])
    error_message = "secrets[*].expiry_rule cannot set both version_expiry_interval and time_of_absolute_expiry."
  }
  validation {
    condition = alltrue([
      for k, v in var.secrets :
      v.replication == null || length(v.replication.targets) > 0
    ])
    error_message = "secrets[*].replication.targets must not be empty."
  }
}
