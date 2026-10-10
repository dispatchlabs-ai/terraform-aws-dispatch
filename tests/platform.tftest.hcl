mock_provider "aws" {
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
variables {
  name               = "dispatch-example"
  availability_zones = ["us-east-1a", "us-east-1b"]
  vpc_cidr           = "10.80.0.0/16"
}
run "aurora_defaults" {
  command = plan
  assert {
    condition     = length(aws_db_instance.this) == 0 && aws_rds_cluster.this[0].engine_mode == "provisioned" && aws_rds_cluster_instance.writer[0].instance_class == "db.serverless"
    error_message = "Default database must be Aurora Serverless v2, not provisioned RDS or Serverless v1."
  }
  assert {
    condition     = aws_rds_cluster.this[0].serverlessv2_scaling_configuration[0].min_capacity == 0.5 && aws_rds_cluster.this[0].serverlessv2_scaling_configuration[0].max_capacity == 4 && aws_rds_cluster.this[0].manage_master_user_password && !aws_rds_cluster_instance.writer[0].publicly_accessible
    error_message = "Bounded autoscaling and private managed-secret database are required."
  }
  assert {
    condition     = aws_rds_cluster.this[0].storage_encrypted && aws_rds_cluster.this[0].deletion_protection && !aws_rds_cluster.this[0].skip_final_snapshot && aws_rds_cluster.this[0].backup_retention_period == 7
    error_message = "Aurora must preserve encryption, retention and deletion protection."
  }
  assert {
    condition     = contains([for p in aws_rds_cluster_parameter_group.this[0].parameter : "${p.name}=${p.value}"], "log_parameter_max_length=0") && contains([for p in aws_rds_cluster_parameter_group.this[0].parameter : "${p.name}=${p.value}"], "log_statement=none")
    error_message = "Credential redaction cannot be lost when selecting Aurora."
  }
}
run "small_rds_option" {
  command = plan
  variables { database_mode = "rds" }
  assert {
    condition     = length(aws_rds_cluster.this) == 0 && aws_db_instance.this[0].instance_class == "db.t4g.small" && aws_db_instance.this[0].manage_master_user_password && aws_db_instance.this[0].storage_encrypted
    error_message = "Keep the explicit small-RDS alternative for cost-sensitive steady workloads."
  }
}
run "short_private_access_logs" {
  command = plan
  assert {
    condition     = aws_s3_bucket_public_access_block.access_logs.block_public_acls && aws_s3_bucket_public_access_block.access_logs.block_public_policy && aws_s3_bucket_public_access_block.access_logs.ignore_public_acls && aws_s3_bucket_public_access_block.access_logs.restrict_public_buckets
    error_message = "ALB access logs must not be public."
  }
  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.access_logs.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256" && one(aws_s3_bucket_lifecycle_configuration.access_logs.rule).expiration[0].days == 7
    error_message = "ALB delivery needs SSE-S3 and short expiration."
  }
  assert {
    condition     = jsondecode(aws_s3_bucket_policy.access_logs.policy).Statement[0].Principal.Service == "logdelivery.elasticloadbalancing.amazonaws.com" && endswith(jsondecode(aws_s3_bucket_policy.access_logs.policy).Statement[0].Resource[0], "/public/AWSLogs/123456789012/*") && jsondecode(aws_s3_bucket_policy.access_logs.policy).Statement[0].Condition.ArnLike["aws:SourceArn"] == "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/*"
    error_message = "Delivery must be scoped to this account, region and known prefixes."
  }
}
run "sanitized_sampled_tracing_contract" {
  command = plan
  assert {
    condition     = local.tracing_environment.backend.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT == "http://127.0.0.1:4318/v1/traces" && local.tracing_environment.worker.OTEL_TRACES_SAMPLER_ARG == "0.1" && !local.tracing_containers.backend[0].essential && local.tracing_containers.backend[0].readonlyRootFilesystem && local.tracing_containers.backend[0].memory == 256
    error_message = "Tracing must be sampled, loopback-only, bounded and nonessential."
  }
  assert {
    condition     = length(aws_iam_role_policy.tracing) == 3 && toset(jsondecode(aws_iam_role_policy.tracing["worker"].policy).Statement[0].Action) == toset(["xray:PutTraceSegments", "xray:PutTelemetryRecords"])
    error_message = "Only ordinary task roles receive X-Ray write permissions."
  }
}
run "tracing_opt_out" {
  command = plan
  variables { enable_tracing = false }
  assert {
    condition     = length(aws_iam_role_policy.tracing) == 0 && length(local.tracing_containers.worker) == 0 && length(local.tracing_environment.backend) == 0
    error_message = "Tracing opt-out must remove sidecars, endpoint settings and grants."
  }
}
run "reject_zero_capacity" {
  command = plan
  variables { aurora_min_capacity = 0 }
  expect_failures = [var.aurora_min_capacity]
}
run "reject_inverted_capacity" {
  command = plan
  variables { aurora_min_capacity = 8 }
  expect_failures = [var.aurora_max_capacity]
}
run "reject_invalid_retention" {
  command = plan
  variables { access_log_retention_days = 0 }
  expect_failures = [var.access_log_retention_days]
}
run "reject_unpinned_collector" {
  command = plan
  variables { tracing_collector_image = "public.ecr.aws/aws-observability/aws-otel-collector:latest" }
  expect_failures = [var.tracing_collector_image]
}
