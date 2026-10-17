variable "name" {
  description = "Unique installation foundation name; changing it replaces named infrastructure."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,29}$", var.name))
    error_message = "Use 3–30 lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "kubernetes_version" {
  description = "Explicit, supported EKS Kubernetes minor version. Review upgrades independently of application updates."
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "Specify a Kubernetes minor version, for example 1.36."
  }
}

variable "vpc_cidr" {
  description = "Dedicated non-overlapping IPv4 /16; public /24 and private /20 subnets are derived from it."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && can(regex("/16$", var.vpc_cidr))
    error_message = "Provide a valid IPv4 /16 CIDR."
  }
}

variable "availability_zones" {
  description = "Two distinct availability zones in the caller's region. One NAT gateway serves both private subnets."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "Specify exactly two distinct availability zones."
  }
}

variable "api_access_cidrs" {
  description = "Explicit operator IPv4 CIDRs allowed to reach the public EKS API; private access remains enabled."
  type        = list(string)

  validation {
    condition = length(var.api_access_cidrs) > 0 && alltrue([
      for cidr in var.api_access_cidrs : can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 24, false)
    ])
    error_message = "Use nonempty IPv4 CIDRs with prefix length /24 or narrower; do not expose the API to the Internet."
  }
}

variable "cluster_admin_arns" {
  description = "Explicit IAM role/user ARNs granted cluster-admin access through EKS access entries; never STS session ARNs."
  type        = set(string)

  validation {
    condition = length(var.cluster_admin_arns) > 0 && alltrue([
      for arn in var.cluster_admin_arns : can(regex("^arn:[^:]+:iam::[0-9]{12}:(role|user)/", arn))
    ])
    error_message = "Provide at least one IAM role/user ARN, not an assumed-role session ARN."
  }
}

variable "node_instance_type" {
  description = "On-demand AMD64 worker instance type. The experiment defaults to one t3.medium; it is not HA."
  type        = string
  default     = "t3.medium"
}

variable "node_count" {
  description = "Explicit desired/minimum node count; no cluster autoscaler is installed by this module."
  type        = number
  default     = 1

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 5 && floor(var.node_count) == var.node_count
    error_message = "Choose 1–5 nodes. Review the cost and singleton maintenance implications before increasing."
  }
}

variable "addon_versions" {
  description = "Pinned EKS add-on versions qualified for the selected Kubernetes minor."
  type = object({
    vpc_cni    = string
    kube_proxy = string
    coredns    = string
    ebs_csi    = string
  })
}

variable "tags" {
  description = "Caller-owned account/environment tags applied to foundation resources."
  type        = map(string)
  default     = {}
}

variable "distributed_postgres" {
  description = "Optional private PostgreSQL for a fresh distributed-worker installation. Null preserves the standalone foundation. Application databases, scoped roles, credentials and initialization remain explicit operator actions."
  type = object({
    engine_version          = string
    instance_class          = optional(string, "db.t4g.small")
    allocated_storage       = optional(number, 20)
    max_allocated_storage   = optional(number, 100)
    backup_retention_period = optional(number, 7)
  })
  default = null

  validation {
    condition     = var.distributed_postgres == null ? true : can(regex("^17\\.[0-9]+$", var.distributed_postgres.engine_version))
    error_message = "Pin a supported PostgreSQL 17 minor version qualified with the application initializer."
  }

  validation {
    condition = var.distributed_postgres == null ? true : (
      var.distributed_postgres.allocated_storage >= 20 &&
      var.distributed_postgres.max_allocated_storage >= var.distributed_postgres.allocated_storage &&
      var.distributed_postgres.max_allocated_storage <= 1000 &&
      floor(var.distributed_postgres.allocated_storage) == var.distributed_postgres.allocated_storage &&
      floor(var.distributed_postgres.max_allocated_storage) == var.distributed_postgres.max_allocated_storage
    )
    error_message = "Use whole-GiB storage values from 20 to 1000, with maximum storage at least the initial allocation."
  }

  validation {
    condition = var.distributed_postgres == null ? true : (
      var.distributed_postgres.backup_retention_period >= 1 &&
      var.distributed_postgres.backup_retention_period <= 35 &&
      floor(var.distributed_postgres.backup_retention_period) == var.distributed_postgres.backup_retention_period
    )
    error_message = "Retain automated database backups for 1 to 35 whole days."
  }
}
