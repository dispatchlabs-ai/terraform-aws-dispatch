locals {
  backend_service_account = "${var.release_name}-backend"
}

terraform {
  required_version = ">= 1.11, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.67" }
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags { tags = var.tags }
}

data "aws_partition" "current" {}

module "foundation" {
  source = "../.."

  name                       = var.name
  kubernetes_version         = var.kubernetes_version
  vpc_cidr                   = var.vpc_cidr
  availability_zones         = var.availability_zones
  api_access_cidrs           = var.api_access_cidrs
  cluster_admin_arns         = var.cluster_admin_arns
  node_count                 = 2
  addon_versions             = var.addon_versions
  network_policy_provider    = "cilium"
  pod_identity_agent_version = var.pod_identity_agent_version
  distributed_postgres       = { engine_version = var.postgres_version }
  tags                       = var.tags
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = var.artifacts_bucket
  force_destroy = false
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# Do not expire noncurrent objects independently of the database/key recovery
# policy. The backend has neither DeleteObject nor ListBucket permissions.
resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_iam_role" "backend" {
  name = "${var.name}-artifacts"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "aws:RequestTag/eks-cluster-arn"            = module.foundation.cluster_arn
          "aws:RequestTag/kubernetes-namespace"       = var.namespace
          "aws:RequestTag/kubernetes-service-account" = local.backend_service_account
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "artifacts" {
  name = "installation-artifacts"
  role = aws_iam_role.backend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "${aws_s3_bucket.artifacts.arn}/${var.artifacts_prefix}/*"
    }]
  })
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RequireTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "BackendMustCreateConditionally"
        Effect    = "Deny"
        Principal = { AWS = aws_iam_role.backend.arn }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.artifacts.arn}/${var.artifacts_prefix}/*"
        Condition = { Null = { "s3:if-none-match" = "true" } }
      },
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.artifacts]
}

resource "aws_eks_pod_identity_association" "backend" {
  cluster_name         = module.foundation.cluster_name
  namespace            = var.namespace
  service_account      = local.backend_service_account
  role_arn             = aws_iam_role.backend.arn
  disable_session_tags = false
  depends_on           = [module.foundation, aws_iam_role_policy.artifacts, aws_s3_bucket_policy.artifacts]
}

resource "aws_ecr_repository" "runtime" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
  encryption_configuration { encryption_type = "AES256" }
  image_scanning_configuration { scan_on_push = true }
}
