mock_provider "aws" {
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/example"
      domain_validation_options = [
        { domain_name = "dispatch.example.com", resource_record_name = "_viewer.dispatch.example.com", resource_record_type = "CNAME", resource_record_value = "_viewer.acm-validations.aws" },
        { domain_name = "origin.dispatch.example.com", resource_record_name = "_origin.dispatch.example.com", resource_record_type = "CNAME", resource_record_value = "_origin.acm-validations.aws" },
        { domain_name = "callbacks.dispatch.example.com", resource_record_name = "_callback.dispatch.example.com", resource_record_type = "CNAME", resource_record_value = "_callback.acm-validations.aws" }
      ]
    }
  }
  mock_resource "aws_cloudfront_function" {
    defaults = { arn = "arn:aws:cloudfront::123456789012:function/example" }
  }
  mock_data "aws_ec2_managed_prefix_list" {
    defaults = { id = "pl-123abc" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { id = "dispatch-example-artifacts", arn = "arn:aws:s3:::dispatch-example-artifacts" }
  }
  mock_resource "aws_subnet" {
    defaults = { id = "subnet-123abc" }
  }
  mock_resource "aws_security_group" {
    defaults = { id = "sg-123abc" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/example" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/example/1234567890123456" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/example/1234567890123456" }
  }
  mock_resource "aws_lb_listener" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/example/1234567890123456/1234567890123456" }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = { arn = "arn:aws:ecs:us-east-1:123456789012:cluster/example" }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = { arn = "arn:aws:ecs:us-east-1:123456789012:task-definition/example:1" }
  }
  mock_resource "aws_service_discovery_service" {
    defaults = { arn = "arn:aws:servicediscovery:us-east-1:123456789012:service/srv-example" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_resource "aws_rds_cluster" {
    defaults = {
      endpoint           = "database.example.internal"
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:master-example", kms_key_id = "example", secret_status = "active" }]
    }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      address            = "database.example.internal"
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:master-example", kms_key_id = "example", secret_status = "active" }]
    }
  }
}
mock_provider "aws" {
  alias = "edge"
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_resource "aws_acm_certificate" {
    defaults = { arn = "arn:aws:acm:us-east-1:123456789012:certificate/edge" }
  }
}

variables {
  name                    = "dispatch-example"
  availability_zones      = ["us-east-1a", "us-east-1b"]
  vpc_cidr                = "10.80.0.0/16"
  service_deployment_mode = { backend = "stop-first", launcher = "stop-first" }
  application = {
    installation_id                = "dispatch-example"
    company_id                     = "example", company_name = "Example"
    origin                         = "https://dispatch.example.com"
    configuration_revision         = "release-example"
    database_ca_pem                = "-----BEGIN CERTIFICATE-----\nexample\n-----END CERTIFICATE-----"
    backend_ca_pem                 = "-----BEGIN CERTIFICATE-----\nexample\n-----END CERTIFICATE-----"
    backend_certificate_pem        = "-----BEGIN CERTIFICATE-----\nexample\n-----END CERTIFICATE-----"
    backend_private_key_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:backend-key-example"
    database_url_secret_arns = {
      auth      = "arn:aws:secretsmanager:us-east-1:123456789012:secret:auth-db-example"
      provider  = "arn:aws:secretsmanager:us-east-1:123456789012:secret:provider-db-example"
      catalog   = "arn:aws:secretsmanager:us-east-1:123456789012:secret:catalog-db-example"
      directory = "arn:aws:secretsmanager:us-east-1:123456789012:secret:directory-db-example"
      routing   = "arn:aws:secretsmanager:us-east-1:123456789012:secret:routing-db-example"
      launcher  = "arn:aws:secretsmanager:us-east-1:123456789012:secret:launcher-db-example"
      workers   = "arn:aws:secretsmanager:us-east-1:123456789012:secret:workers-db-example"
    }
    encryption_key_secret_arns = {
      auth     = "arn:aws:secretsmanager:us-east-1:123456789012:secret:auth-key-example"
      provider = "arn:aws:secretsmanager:us-east-1:123456789012:secret:provider-key-example"
      catalog  = "arn:aws:secretsmanager:us-east-1:123456789012:secret:catalog-key-example"
    }
    token_secret_arns = {
      worker        = "arn:aws:secretsmanager:us-east-1:123456789012:secret:worker-token-example"
      launcher      = "arn:aws:secretsmanager:us-east-1:123456789012:secret:launcher-token-example"
      operator      = "arn:aws:secretsmanager:us-east-1:123456789012:secret:operator-token-example"
      backend_peer  = "arn:aws:secretsmanager:us-east-1:123456789012:secret:backend_peer-token-example"
      launcher_peer = "arn:aws:secretsmanager:us-east-1:123456789012:secret:launcher_peer-token-example"
    }
  }
}
run "foundation" {
  command = plan
  assert {
    condition     = length(aws_ecs_service.stable) == 0 && length(aws_ecs_task_definition.worker) == 0
    error_message = "Foundation must not start executors or register worker images."
  }
  assert {
    condition     = aws_rds_cluster.this[0].deletion_protection && aws_rds_cluster.this[0].storage_encrypted
    error_message = "Persistent database must be protected and encrypted."
  }
}
run "public_images" {
  command = plan
  variables {
    image                       = "ghcr.io/dispatchlabs-ai/dispatch@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    worker_image                = "ghcr.io/dispatchlabs-ai/dispatch-worker@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    worker_package_installation = true
    certificate_arn             = "arn:aws:acm:us-east-1:123456789012:certificate/example"
  }
  assert {
    condition     = aws_ecs_service.stable["backend"].desired_count == 0 && aws_ecs_service.stable["launcher"].desired_count == 0
    error_message = "Task registration must not activate application admission."
  }
  assert {
    condition     = aws_lb_target_group.backend[0].deregistration_delay == "30" && aws_lb.this[0].idle_timeout == 300
    error_message = "Default drain budget must be short and independently bounded."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.worker[0].container_definitions)[0].image == var.worker_image && jsondecode(aws_ecs_task_definition.worker[0].container_definitions)[0].user == "0:0"
    error_message = "Ubuntu worker selection must remain separate from hardened controllers."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.stable["backend"].container_definitions)[1].readonlyRootFilesystem && jsondecode(aws_ecs_task_definition.stable["backend"].container_definitions)[1].user == "65532:65532"
    error_message = "Controller hardening must not inherit trusted worker permissions."
  }
}
run "reject_unpinned_image" {
  command = plan
  variables { image = "ghcr.io/dispatchlabs-ai/dispatch:latest" }
  expect_failures = [var.image]
}
run "reject_duplicate_zones" {
  command = plan
  variables { availability_zones = ["us-east-1a", "us-east-1a"] }
  expect_failures = [var.availability_zones]
}
run "reject_wildcard_pull_authority" {
  command = plan
  variables { image_pull_repository_arns = ["arn:aws:ecr:us-east-1:123456789012:repository/*"] }
  expect_failures = [var.image_pull_repository_arns]
}
run "activation_is_explicit_and_scoped" {
  command = plan
  variables {
    image             = "ghcr.io/dispatchlabs-ai/dispatch@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    enable_activation = true
  }
  assert {
    condition     = length(jsondecode(aws_ecs_task_definition.activation[0].container_definitions)[0].secrets) == 1 && jsondecode(aws_ecs_task_definition.activation[0].container_definitions)[0].secrets[0].valueFrom == var.application.token_secret_arns.operator
    error_message = "Activation may receive only the operator token, never database or service secret bundles."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.activation_backend[0].from_port == 3001 && length(aws_ecs_service.stable) == 2
    error_message = "Activation must use dedicated private API ingress and remain outside ECS services."
  }
}
run "initializer_scope" {
  command = plan
  variables {
    image                       = "ghcr.io/dispatchlabs-ai/dispatch@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    enable_database_initializer = true
  }
  assert {
    condition     = length(local.generated_database_initializer.secrets) == 8 && !contains(values(local.generated_services.backend.secrets), local.database_master_secret_arn) && length(local.generated_services.launcher.secrets) == 3
    error_message = "Only initializer gets master plus seven DB URLs; launcher gets its journal and two shared tokens."
  }
  assert {
    condition     = jsondecode(local.role_public_files[0].backend["directory.json"]).storeId == "dispatch-example:directory" && jsondecode(local.role_public_files[0].backend["routing.json"]).installationId == "dispatch-example"
    error_message = "Persistent stores must preserve their distinct identity contracts."
  }
}
run "rolling_configuration" {
  command = plan
  variables {
    image                            = "ghcr.io/dispatchlabs-ai/dispatch@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    launcher_internal_alb            = true
    certificate_arn                  = "arn:aws:acm:us-east-1:123456789012:certificate/example"
    backend_callback_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/callback"
    service_deployment_mode          = { backend = "rolling", launcher = "rolling" }
  }
  assert {
    condition     = aws_ecs_service.stable["backend"].deployment_minimum_healthy_percent == 100 && aws_ecs_task_definition.worker[0].skip_destroy
    error_message = "Rolling must preserve old worker task revisions and readiness-gated controller overlap."
  }
  assert {
    condition     = local.generated_services.backend.environment.DISPATCH_CONTROLLER_CONFIG_FILE == "/tmp/dispatch-bootstrap/controller.json" && local.generated_services.launcher.environment.DISPATCH_CONTROLLER_CONFIG_FILE == "/tmp/dispatch-bootstrap/controller.json"
    error_message = "Both rolling roles need explicit native controller configuration."
  }
}

run "managed_domain_baseline" {
  command = plan
  variables {
    image  = "ghcr.io/dispatchlabs-ai/dispatch@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    domain = { name = "dispatch.example.com", zone_id = "Z123EXAMPLE" }
    application = {
      installation_id                = "dispatch-example", company_id = "example", company_name = "Example"
      origin                         = "https://dispatch.example.com", configuration_revision = "release-example"
      database_ca_pem                = "-----BEGIN CERTIFICATE-----fixture"
      backend_ca_pem                 = "-----BEGIN CERTIFICATE-----fixture"
      callback_ca_pem                = "-----BEGIN CERTIFICATE-----public-acm-trust"
      backend_certificate_pem        = "-----BEGIN CERTIFICATE-----fixture"
      backend_private_key_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:backend-key-example"
      database_url_secret_arns       = { for k in ["auth", "provider", "catalog", "directory", "routing", "launcher", "workers"] : k => "arn:aws:secretsmanager:us-east-1:123456789012:secret:${k}-db-example" }
      encryption_key_secret_arns     = { for k in ["auth", "provider", "catalog"] : k => "arn:aws:secretsmanager:us-east-1:123456789012:secret:${k}-key-example" }
      token_secret_arns              = { for k in ["worker", "launcher", "operator", "backend_peer", "launcher_peer"] : k => "arn:aws:secretsmanager:us-east-1:123456789012:secret:${k}-token-example" }
    }
    service_deployment_mode = { backend = "rolling", launcher = "rolling" }
  }
  assert {
    condition     = aws_lb.this[0].internal && aws_cloudfront_vpc_origin.backend[0].vpc_origin_endpoint_config[0].origin_protocol_policy == "https-only"
    error_message = "CloudFront API origin must remain private and TLS-only."
  }
  assert {
    condition     = aws_cloudfront_cache_policy.api[0].max_ttl == 0 && length(aws_cloudfront_distribution.frontend[0].custom_error_response) == 0
    error_message = "API responses must never be cached or globally rewritten into SPA HTML."
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.frontend[0].block_public_policy && aws_cloudfront_origin_access_control.frontend[0].signing_behavior == "always"
    error_message = "Static frontend storage must be private behind signed OAC reads."
  }
  assert {
    condition     = local.generated_services.backend.environment.DISPATCH_SERVE_CLIENT == "false" && local.generated_callback_url == "https://callbacks.dispatch.example.com"
    error_message = "Managed delivery needs API-only backend and private stable callbacks."
  }
}
