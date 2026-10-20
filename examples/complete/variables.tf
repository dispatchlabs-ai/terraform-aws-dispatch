variable "account_id" {
  description = "Expected AWS account; the provider refuses credentials for a different account."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Provide the intended twelve-digit AWS account ID."
  }
}

variable "region" {
  description = "AWS region containing both availability zones."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Unique installation resource prefix."
  type        = string
  default     = "dispatch"
}

variable "kubernetes_version" {
  description = "Supported EKS Kubernetes minor version."
  type        = string
}

variable "addon_versions" {
  description = "Pinned add-on builds supported for the selected EKS version and region."
  type        = object({ vpc_cni = string, kube_proxy = string, coredns = string, ebs_csi = string })
}

variable "pod_identity_agent_version" {
  description = "Pinned compatible EKS Pod Identity Agent build; required for backend S3 access."
  type        = string
  nullable    = false
}

variable "postgres_version" {
  description = "Supported RDS PostgreSQL 17 minor version."
  type        = string
}

variable "vpc_cidr" {
  description = "Dedicated non-overlapping IPv4 /16."
  type        = string
  default     = "10.50.0.0/16"
}

variable "availability_zones" {
  description = "Two distinct availability zones within region."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "api_access_cidrs" {
  description = "Operator public IPv4 CIDRs, /24 or narrower, allowed to reach the EKS API."
  type        = list(string)
}

variable "cluster_admin_arns" {
  description = "Explicit IAM users/roles granted cluster administration; never STS session ARNs."
  type        = set(string)
}

variable "artifacts_bucket" {
  description = "Globally unique name for a new private artifact bucket."
  type        = string
}

variable "artifacts_prefix" {
  description = "Installation object prefix without leading/trailing slashes or IAM wildcards."
  type        = string
  default     = "dispatch"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9/_-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]$", var.artifacts_prefix))
    error_message = "Use letters, digits, slash, underscore or hyphen, starting and ending with a letter or digit."
  }
}

variable "namespace" {
  description = "Kubernetes namespace used when installing the application chart."
  type        = string
  default     = "dispatch"
}

variable "release_name" {
  description = "Helm release name; the chart derives its backend ServiceAccount from this value."
  type        = string
  default     = "dispatch"
  validation {
    condition     = length(var.release_name) <= 53 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "Use 1–53 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
  }
}

variable "tags" {
  description = "Caller tags for foundation and application infrastructure."
  type        = map(string)
  default     = {}
}
