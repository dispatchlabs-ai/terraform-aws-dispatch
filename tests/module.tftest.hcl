mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      address            = "database.example.internal"
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:master-example", kms_key_id = "example", secret_status = "active" }]
    }
  }
}
variables {
  name               = "dispatch-example"
  availability_zones = ["us-east-1a", "us-east-1b"]
  vpc_cidr           = "10.80.0.0/16"
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
    condition     = aws_db_instance.this.deletion_protection && aws_db_instance.this.storage_encrypted
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
