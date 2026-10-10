terraform {
  required_version = ">= 1.12.6, < 2.0.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "= 6.67.0" }
  }
}

provider "aws" { region = var.region }

module "dispatch" {
  # Run this example from a checked-out immutable module release.
  # An external root may instead use the repository Git URL with ?ref=<commit>.
  source = "../.."

  name               = var.name
  availability_zones = var.availability_zones
  vpc_cidr           = var.vpc_cidr
  tags               = var.tags

  image                       = var.image
  worker_image                = var.worker_image
  worker_package_installation = var.worker_image != null
  cpu_architecture            = var.cpu_architecture
  application                 = var.application

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
  enable_database_initializer   = var.enable_database_initializer
  enable_credential_maintenance = var.enable_credential_maintenance
}

output "database_address" { value = module.dispatch.database_address }
output "database_master_secret_arn" { value = module.dispatch.database_master_secret_arn }
output "service_cluster_arn" { value = module.dispatch.service_cluster_arn }
output "worker_cluster_arn" { value = module.dispatch.worker_cluster_arn }
output "private_subnet_ids" { value = module.dispatch.private_subnet_ids }
output "worker_task_definition_arn" { value = module.dispatch.worker_task_definition_arn }
output "database_initializer" { value = module.dispatch.database_initializer }
output "activation" { value = module.dispatch.activation }
output "credential_maintenance" { value = module.dispatch.credential_maintenance }
output "alb_dns_name" { value = module.dispatch.alb_dns_name }
output "alb_zone_id" { value = module.dispatch.alb_zone_id }
output "backend_private_url" { value = module.dispatch.backend_private_url }
