variable "region" { type = string }
variable "name" { type = string }
variable "availability_zones" { type = list(string) }
variable "vpc_cidr" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
variable "image" {
  type    = string
  default = null
}
variable "worker_image" {
  type    = string
  default = null
}
variable "cpu_architecture" {
  type    = string
  default = "ARM64"
}
variable "certificate_arn" {
  type    = string
  default = null
}
variable "backend_callback_certificate_arn" {
  type    = string
  default = null
}
variable "internal_alb" {
  type    = bool
  default = true
}
variable "client_cidrs" {
  type    = set(string)
  default = []
}
variable "secret_kms_key_arns" {
  type    = set(string)
  default = []
}
variable "desired_count" {
  type    = number
  default = 0
}
variable "service_deployment_mode" {
  type    = map(string)
  default = {}
}
variable "enable_database_initializer" {
  type    = bool
  default = false
}
variable "enable_credential_maintenance" {
  type    = bool
  default = false
}
variable "application" {
  description = "Nonsecret generated-configuration inputs. Supply secret ARNs, never their resolved values. Null prepares foundation only."
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
    database_url_secret_arns = object({
      auth    = string, provider = string, catalog = string, directory = string,
      routing = string, launcher = string, workers = string
    })
    encryption_key_secret_arns = object({ auth = string, provider = string, catalog = string })
    token_secret_arns = object({
      worker       = string, launcher = string, operator = string,
      backend_peer = string, launcher_peer = string
    })
  })
  default = null
}

variable "enable_activation" {
  type    = bool
  default = false
}
variable "service_desired_counts" {
  type    = map(number)
  default = {}
}

variable "image_pull_repository_arns" {
  type    = set(string)
  default = []
}
variable "deregistration_delay_seconds" {
  type    = number
  default = 30
}
variable "idle_timeout_seconds" {
  type    = number
  default = 300
}

variable "domain" {
  description = "Final application hostname and existing public Route 53 hosted zone. Null prepares foundation without managed ingress."
  type        = object({ name = string, zone_id = string })
  default     = null
}
variable "database_mode" {
  type    = string
  default = "aurora-serverless"
}
variable "aurora_engine_version" {
  type    = string
  default = "18.6.1"
}
variable "aurora_min_capacity" {
  type    = number
  default = 0.5
}
variable "aurora_max_capacity" {
  type    = number
  default = 4
}
variable "enable_tracing" {
  type    = bool
  default = true
}

variable "frontend_release_prefix" {
  description = "Immutable SPA release prefix; publish and verify the complete bundle before selecting a new prefix."
  type        = string
  default     = "releases/initial"
}
variable "trace_sample_ratio" {
  type    = number
  default = 0.1
}
variable "access_log_retention_days" {
  type    = number
  default = 7
}

variable "worker_capacity_provider" {
  description = "FARGATE_SPOT is opt-in for workers only and needs interruption/recovery qualification."
  type        = string
  default     = "FARGATE"
}
variable "log_retention_days" {
  type    = number
  default = 7
}
