variable "database_mode" {
  description = "Fresh installation choice: autoscaling Aurora Serverless v2 or small provisioned RDS. Changing mode is not a data migration."
  type        = string
  default     = "aurora-serverless"
  validation {
    condition     = contains(["aurora-serverless", "rds"], var.database_mode)
    error_message = "Choose aurora-serverless or rds."
  }
}
variable "aurora_engine_version" {
  description = "Pinned Aurora PostgreSQL version. Confirm regional db.serverless support before apply; no automatic major upgrades."
  type        = string
  default     = "18.6.1"
  validation {
    condition     = can(regex("^(17|18)\\.[0-9]+(\\.[0-9]+)?$", var.aurora_engine_version))
    error_message = "Use an explicit Aurora PostgreSQL 17 or 18 minor/patch version."
  }
}
variable "aurora_min_capacity" {
  description = "Minimum ACUs. Keep at least 0.5: Dispatch retains owner connections and is not an auto-pause workload."
  type        = number
  default     = 0.5
  validation {
    condition     = var.aurora_min_capacity >= 0.5 && var.aurora_min_capacity <= 128 && floor(var.aurora_min_capacity * 2) == var.aurora_min_capacity * 2
    error_message = "Use 0.5–128 ACUs in half-ACU increments; scale-to-zero is deliberately excluded."
  }
}
variable "aurora_max_capacity" {
  description = "Autoscaling ceiling in ACUs; a spend bound, not a guarantee of sufficient capacity."
  type        = number
  default     = 4
  validation {
    condition     = var.aurora_max_capacity >= var.aurora_min_capacity && var.aurora_max_capacity <= 128 && floor(var.aurora_max_capacity * 2) == var.aurora_max_capacity * 2
    error_message = "Use half-ACU increments up to 128 and no less than the minimum."
  }
}
