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
  description = "Minimum ACUs. Zero enables auto-pause only after every application/operator connection closes; running owners prevent pause."
  type        = number
  default     = 0.5
  validation {
    condition     = var.aurora_min_capacity >= 0 && var.aurora_min_capacity <= 128 && floor(var.aurora_min_capacity * 2) == var.aurora_min_capacity * 2
    error_message = "Use 0–128 ACUs in half-ACU increments; zero requires an auto-pause-capable engine and region."
  }
}
variable "aurora_max_capacity" {
  description = "Autoscaling ceiling in ACUs; a spend bound, not a guarantee of sufficient capacity."
  type        = number
  default     = 4
  validation {
    condition     = var.aurora_max_capacity >= 0.5 && var.aurora_max_capacity >= var.aurora_min_capacity && var.aurora_max_capacity <= 128 && floor(var.aurora_max_capacity * 2) == var.aurora_max_capacity * 2
    error_message = "Use 0.5–128 ACUs in half-ACU increments and no less than the minimum."
  }
}
variable "aurora_seconds_until_auto_pause" {
  description = "Connection-free interval before Aurora may pause when min capacity is zero. Does not retire Dispatch tasks or close their owner connections."
  type        = number
  default     = 300
  validation {
    condition     = var.aurora_seconds_until_auto_pause >= 300 && var.aurora_seconds_until_auto_pause <= 86400 && floor(var.aurora_seconds_until_auto_pause) == var.aurora_seconds_until_auto_pause
    error_message = "Use a whole number of seconds from 300 to 86400."
  }
}
