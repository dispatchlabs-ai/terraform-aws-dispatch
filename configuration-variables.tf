variable "application" {
  description = "Typed Dispatch configuration. Supply secret ARNs, never secret values. Null prepares infrastructure only. Certificate/CA PEMs are public material."
  type = object({
    installation_id                = string
    company_id                     = string
    company_name                   = string
    origin                         = string
    configuration_revision         = string
    database_ca_pem                = string
    backend_ca_pem                 = string
    callback_ca_pem                = optional(string)
    backend_certificate_pem        = string
    backend_private_key_secret_arn = string
    github = optional(object({
      broker_origin    = string
      token_secret_arn = string
      manager_user_ids = set(string)
    }))
    database_url_secret_arns = object({
      auth    = string, provider = string, catalog = string, directory = string,
      routing = string, launcher = string, workers = string
    })
    encryption_key_secret_arns = object({ auth = string, provider = string, catalog = string })
    token_secret_arns = object({
      worker = string, launcher = string, operator = string, backend_peer = string, launcher_peer = string
    })
  })
  default = null
  validation {
    condition = var.application == null ? true : (
      can(regex("^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$", var.application.installation_id)) &&
      length(var.application.company_id) > 0 && length(var.application.company_id) <= 100 &&
      length(var.application.company_name) > 0 && length(var.application.company_name) <= 100 &&
      length(var.application.configuration_revision) > 0 && length(var.application.configuration_revision) <= 200 &&
      can(regex("^https://[A-Za-z0-9.-]+(:[0-9]+)?$", var.application.origin))
    )
    error_message = "Supply stable installation/company identities, a 1–200 character worker configuration revision, and an HTTPS origin without credentials, path or trailing slash."
  }
  validation {
    condition = var.application == null ? true : alltrue([
      for arn in concat(values(var.application.database_url_secret_arns), values(var.application.encryption_key_secret_arns), values(var.application.token_secret_arns), [var.application.backend_private_key_secret_arn], var.application.github == null ? [] : [var.application.github.token_secret_arn]) :
      can(regex("^arn:aws(-us-gov)?:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:[A-Za-z0-9/_+=.@-]+$", arn))
    ])
    error_message = "Supply full Secrets Manager secret ARNs (not values or JSON-key/version selectors). Secret contents are delivered only by ECS."
  }
  validation {
    condition = var.application == null ? true : var.application.github == null ? true : (
      can(regex("^https://[A-Za-z0-9.-]+(:[0-9]+)?$", var.application.github.broker_origin)) &&
      length(var.application.github.manager_user_ids) > 0 &&
      alltrue([for user_id in var.application.github.manager_user_ids : length(trimspace(user_id)) > 0])
    )
    error_message = "GitHub requires an HTTPS broker origin without a path or credentials and an explicit nonempty set of authenticated connection-manager user IDs."
  }
  validation {
    condition = var.application == null ? true : (
      length(distinct(values(var.application.database_url_secret_arns))) == 7 &&
      length(distinct(values(var.application.encryption_key_secret_arns))) == 3 &&
      length(distinct(values(var.application.token_secret_arns))) == 5
    )
    error_message = "Each database, encryption key and token must have its own retained secret reference within its group."
  }
  validation {
    condition = var.application == null ? true : alltrue([
      for pem in [var.application.database_ca_pem, var.application.backend_ca_pem, var.application.backend_certificate_pem, coalesce(var.application.callback_ca_pem, var.application.backend_ca_pem)] :
      strcontains(pem, "-----BEGIN CERTIFICATE-----") && !strcontains(pem, "PRIVATE KEY")
    ])
    error_message = "CA and certificate inputs must contain public certificate PEM, never private keys."
  }
}

variable "enable_database_initializer" {
  description = "Register the operator-only database initializer (verification command by default). Requires application configuration and stopped controllers; does not run it."
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_database_initializer || var.application != null
    error_message = "Database initialization requires application configuration."
  }
}

variable "enable_credential_maintenance" {
  description = "Register a private operator credential terminal with auth/provider secrets only. Requires stopped backend; does not run it."
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_credential_maintenance || var.application != null
    error_message = "Credential maintenance requires application configuration."
  }
}
