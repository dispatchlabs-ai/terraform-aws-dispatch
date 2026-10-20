output "installation" {
  description = "Non-secret platform, chart and initializer metadata. The master secret ARN is operator-only."
  value = {
    release                 = var.release_name
    namespace               = var.namespace
    backend_service_account = local.backend_service_account
    cluster = {
      name     = module.foundation.cluster_name
      arn      = module.foundation.cluster_arn
      endpoint = module.foundation.cluster_endpoint
    }
    postgres = module.foundation.distributed_postgres
    artifacts = {
      provider                    = "s3"
      endpoint                    = "https://s3.${var.region}.${data.aws_partition.current.dns_suffix}"
      region                      = var.region
      bucket                      = aws_s3_bucket.artifacts.id
      prefix                      = var.artifacts_prefix
      credentials_mode            = "podIdentity"
      backend_identity            = aws_iam_role.backend.arn
      service_account_annotations = {}
    }
    registry = aws_ecr_repository.runtime.repository_url
    gateway = {
      vpc_id                            = module.foundation.vpc_id
      public_subnet_ids                 = module.foundation.public_subnet_ids
      load_balancer_controller_role_arn = module.foundation.load_balancer_controller_role_arn
    }
  }
  depends_on = [aws_eks_pod_identity_association.backend, aws_s3_bucket_versioning.artifacts]
}

output "helm_values" {
  description = "Partial Dispatch chart values. Export as JSON and merge with your reviewed platform/application values; no credentials are included."
  value = {
    postgres = {
      host = module.foundation.distributed_postgres.host
      port = module.foundation.distributed_postgres.port
    }
    artifacts = {
      kind            = "s3"
      endpoint        = "https://s3.${var.region}.${data.aws_partition.current.dns_suffix}"
      region          = var.region
      bucket          = aws_s3_bucket.artifacts.id
      prefix          = var.artifacts_prefix
      credentialsMode = "podIdentity"
    }
    networkPolicy = {
      databaseCidrs    = module.foundation.distributed_postgres.private_subnet_cidrs
      podIdentityCidrs = ["169.254.170.23/32"]
    }
  }
}
