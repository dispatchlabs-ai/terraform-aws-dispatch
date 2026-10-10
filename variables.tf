variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.name))
    error_message = "Use a 3–20 character lowercase installation name."
  }
}
variable "availability_zones" {
  type = list(string)
  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "Supply exactly two distinct availability zones."
  }
}
variable "vpc_cidr" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}
variable "database_instance_class" {
  type    = string
  default = "db.t4g.small"
}
variable "database_engine_version" {
  type    = string
  default = "17"
  validation {
    condition     = can(regex("^17(\\.[0-9]+)?$", var.database_engine_version))
    error_message = "This module uses the PostgreSQL 17 parameter family."
  }
}
variable "database_storage_gib" {
  type    = number
  default = 20
}
variable "log_retention_days" {
  type    = number
  default = 7
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30], var.log_retention_days)
    error_message = "Select short CloudWatch retention: 1, 3, 5, 7, 14 or 30 days."
  }
}
variable "image" {
  description = "Immutable controller OCI registry digest (and worker fallback). Null prepares foundation only."
  type        = string
  default     = null
  validation {
    condition     = var.image == null ? true : can(regex("@sha256:[a-f0-9]{64}$", var.image))
    error_message = "Use an immutable registry digest."
  }
}
variable "worker_image" {
  description = "Optional separate immutable worker image; null retains the controller image."
  type        = string
  default     = null
  validation {
    condition     = var.worker_image == null ? true : can(regex("@sha256:[a-f0-9]{64}$", var.worker_image))
    error_message = "Use an immutable worker registry digest."
  }
}
variable "worker_package_installation" {
  description = "Opt in to trusted root workers with writable disposable root and ordinary container capabilities. Controllers remain hardened."
  type        = bool
  default     = false
}
variable "cpu_architecture" {
  type    = string
  default = "ARM64"
  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "Select ARM64 or X86_64."
  }
}
variable "secret_kms_key_arns" {
  type    = set(string)
  default = []
}
variable "desired_count" {
  description = "Explicit activation after bootstrap and owner checks; never more than one backend/launcher."
  type        = number
  default     = 0
  validation {
    condition     = contains([0, 1], var.desired_count)
    error_message = "Only zero or one stable service owner is supported."
  }
}
variable "certificate_arn" {
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
variable "backend_health_check_path" {
  description = "ALB process-liveness path. Use /internal/health with a supporting image; it must remain healthy during intentional drain. Public /internal access stays blocked."
  type        = string
  default     = "/internal/health"
  validation {
    condition     = startswith(var.backend_health_check_path, "/")
    error_message = "Health check path must start with /."
  }
}

variable "service_desired_counts" {
  description = "Optional per-controller zero/one overrides for ordered maintenance: stop backend and confirm termination before stopping launcher."
  type        = map(number)
  default     = {}
  validation {
    condition     = alltrue([for role, count in var.service_desired_counts : contains(["backend", "launcher"], role) && contains([0, 1], count)])
    error_message = "Only backend/launcher zero-or-one overrides are supported."
  }
}

variable "service_deployment_mode" {
  description = "Controllers default to readiness-gated rolling (100/200). Stop-first is an explicit maintenance choice, not a zero-downtime deployment."
  type        = map(string)
  default     = { backend = "rolling", launcher = "rolling" }
  validation {
    condition     = alltrue([for role, mode in var.service_deployment_mode : contains(["backend", "launcher"], role) && contains(["stop-first", "rolling"], mode)])
    error_message = "Select stop-first or rolling for backend and/or launcher only."
  }
}

variable "launcher_internal_alb" {
  description = "Use a private launcher ALB for managed request withdrawal/draining. Requires a readiness-capable image; migrate callers before enabling rolling."
  type        = bool
  default     = true
}

variable "backend_callback_certificate_arn" {
  description = "Optional ACM certificate for callbacks.<name>.internal on the private ALB. Requires launcher_internal_alb and a readiness-capable backend. The certificate must match backend_callback_hostname and chain to the workers' configured CA bundle."
  type        = string
  default     = null
  validation {
    condition     = var.backend_callback_certificate_arn == null || var.launcher_internal_alb
    error_message = "Backend callback ingress reuses the private ALB; enable launcher_internal_alb."
  }
}

variable "deregistration_delay_seconds" {
  description = "ALB request-drain allowance. Short values permit interrupted requests; they do not bypass controller ownership."
  type        = number
  default     = 30
  validation {
    condition     = var.deregistration_delay_seconds >= 0 && var.deregistration_delay_seconds <= 3600 && floor(var.deregistration_delay_seconds) == var.deregistration_delay_seconds
    error_message = "Use an integer from 0 to 3600 seconds."
  }
}
variable "idle_timeout_seconds" {
  description = "ALB idle connection timeout, independent of application request bounds and task stop allowance."
  type        = number
  default     = 300
  validation {
    condition     = var.idle_timeout_seconds >= 1 && var.idle_timeout_seconds <= 4000 && floor(var.idle_timeout_seconds) == var.idle_timeout_seconds
    error_message = "Use an integer from 1 to 4000 seconds."
  }
}
variable "image_pull_repository_arns" {
  description = "Additional exact private ECR repository ARNs authorized for image pulls. Public GHCR pulls need no ECR grant."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for arn in var.image_pull_repository_arns : can(regex("^arn:[a-z-]+:ecr:[a-z0-9-]+:[0-9]{12}:repository/[^*?]+$", arn))])
    error_message = "Supply exact ECR repository ARNs, never wildcards."
  }
}
