terraform {
  required_version = ">= 1.12.6, < 2.0.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "= 6.67.0" }
  }
}

provider "aws" { region = var.region }
provider "aws" {
  alias  = "edge"
  region = "us-east-1"
}

module "dispatch" {
  # Run this example from a checked-out immutable module release.
  # An external root may instead use the repository Git URL with ?ref=<commit>.
  source = "../.."
  providers = {
    aws      = aws
    aws.edge = aws.edge
  }

  name                    = var.name
  availability_zones      = var.availability_zones
  vpc_cidr                = var.vpc_cidr
  tags                    = var.tags
  task_egress             = var.task_egress
  domain                  = var.domain
  frontend_release_prefix = var.frontend_release_prefix

  database_mode                   = var.database_mode
  aurora_engine_version           = var.aurora_engine_version
  aurora_min_capacity             = var.aurora_min_capacity
  aurora_max_capacity             = var.aurora_max_capacity
  aurora_seconds_until_auto_pause = var.aurora_seconds_until_auto_pause
  enable_tracing                  = var.enable_tracing
  trace_sample_ratio              = var.trace_sample_ratio
  access_log_retention_days       = var.access_log_retention_days

  image                       = var.image
  worker_image                = var.worker_image
  worker_package_installation = var.worker_image != null
  cpu_architecture            = var.cpu_architecture
  image_pull_repository_arns  = var.image_pull_repository_arns
  application                 = var.application

  worker_capacity_provider = var.worker_capacity_provider
  log_retention_days       = var.log_retention_days

  certificate_arn                  = var.certificate_arn
  internal_alb                     = var.internal_alb
  client_cidrs                     = var.client_cidrs
  backend_health_check_path        = "/internal/health"
  launcher_internal_alb            = true
  backend_callback_certificate_arn = var.backend_callback_certificate_arn
  secret_kms_key_arns              = var.secret_kms_key_arns

  enable_activation             = var.enable_activation
  service_desired_counts        = var.service_desired_counts
  desired_count                 = var.desired_count
  service_deployment_mode       = var.service_deployment_mode
  deregistration_delay_seconds  = var.deregistration_delay_seconds
  idle_timeout_seconds          = var.idle_timeout_seconds
  enable_database_initializer   = var.enable_database_initializer
  enable_credential_maintenance = var.enable_credential_maintenance
}

output "database_address" { value = module.dispatch.database_address }
output "database_master_secret_arn" { value = module.dispatch.database_master_secret_arn }
output "service_cluster_arn" { value = module.dispatch.service_cluster_arn }
output "worker_cluster_arn" { value = module.dispatch.worker_cluster_arn }
output "private_subnet_ids" { value = module.dispatch.private_subnet_ids }
output "task_subnet_ids" { value = module.dispatch.task_subnet_ids }
output "task_assign_public_ip" { value = module.dispatch.task_assign_public_ip }
output "worker_task_definition_arn" { value = module.dispatch.worker_task_definition_arn }
output "database_initializer" { value = module.dispatch.database_initializer }
output "activation" { value = module.dispatch.activation }
output "credential_maintenance" { value = module.dispatch.credential_maintenance }
output "alb_dns_name" { value = module.dispatch.alb_dns_name }
output "alb_zone_id" { value = module.dispatch.alb_zone_id }
output "backend_private_url" { value = module.dispatch.backend_private_url }

output "frontend_bucket" { value = module.dispatch.frontend_bucket }
output "frontend_distribution_id" { value = module.dispatch.frontend_distribution_id }
output "frontend_release_prefix" { value = module.dispatch.frontend_release_prefix }
output "access_log_bucket" { value = module.dispatch.access_log_bucket }
