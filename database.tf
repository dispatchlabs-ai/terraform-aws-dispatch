resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = aws_subnet.private[*].id
  tags       = local.tags
}
resource "aws_db_parameter_group" "this" {
  count       = var.database_mode == "rds" ? 1 : 0
  name_prefix = "${var.name}-"
  family      = "postgres17"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  # RDS restricts session SET for these even for its managed master identity.
  # Suppress bound values at the dedicated database boundary, without role grants.
  parameter {
    name         = "log_parameter_max_length"
    value        = "0"
    apply_method = "immediate"
  }
  parameter {
    name         = "log_parameter_max_length_on_error"
    value        = "0"
    apply_method = "immediate"
  }
  # Worker provisioning also sends role DDL; bound-value limits do not redact SQL literals.
  # Fail-closed application checks must verify these effective settings before password DDL.
  dynamic "parameter" {
    for_each = {
      log_statement                      = "none"
      log_min_duration_statement         = "-1"
      log_min_duration_sample            = "-1"
      log_min_error_statement            = "panic"
      log_error_verbosity                = "terse"
      "pg_stat_statements.track_utility" = "0"
    }
    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "immediate"
    }
  }
  tags = local.tags
}
resource "aws_db_instance" "this" {
  count                 = var.database_mode == "rds" ? 1 : 0
  identifier            = var.name
  engine                = "postgres"
  engine_version        = var.database_engine_version
  instance_class        = var.database_instance_class
  allocated_storage     = var.database_storage_gib
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true
  # Use PostgreSQL's default maintenance database. The operator initializer owns
  # the seven application databases; RDS rejects "dispatch" as an initial DBName.
  username                    = "dispatch_operator"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.this.name
  parameter_group_name        = aws_db_parameter_group.this[0].name
  vpc_security_group_ids      = [aws_security_group.database.id]
  publicly_accessible         = false
  multi_az                    = false
  backup_retention_period     = 7
  copy_tags_to_snapshot       = true
  deletion_protection         = true
  skip_final_snapshot         = false
  final_snapshot_identifier   = "${var.name}-final"
  auto_minor_version_upgrade  = true
  apply_immediately           = false
  tags                        = local.tags
  lifecycle { prevent_destroy = true }
}
# Aurora Serverless v2 uses provisioned engine_mode + db.serverless instances.
# One writer keeps the baseline small; this is not reader-backed instant failover.
resource "aws_rds_cluster_parameter_group" "this" {
  count       = var.database_mode == "aurora-serverless" ? 1 : 0
  name_prefix = "${var.name}-aurora-"
  family      = "aurora-postgresql${split(".", var.aurora_engine_version)[0]}"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  # Preserve initializer/password-DDL fail-closed redaction checks on both engines.
  dynamic "parameter" {
    for_each = {
      log_parameter_max_length           = "0"
      log_parameter_max_length_on_error  = "0"
      log_statement                      = "none"
      log_min_duration_statement         = "-1"
      log_min_duration_sample            = "-1"
      log_min_error_statement            = "panic"
      log_error_verbosity                = "terse"
      "pg_stat_statements.track_utility" = "0"
    }
    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "immediate"
    }
  }
  tags = local.tags
}
resource "aws_rds_cluster" "this" {
  count                           = var.database_mode == "aurora-serverless" ? 1 : 0
  cluster_identifier              = var.name
  engine                          = "aurora-postgresql"
  engine_mode                     = "provisioned"
  engine_version                  = var.aurora_engine_version
  master_username                 = "dispatch_operator"
  manage_master_user_password     = true
  storage_encrypted               = true
  storage_type                    = "aurora"
  db_subnet_group_name            = aws_db_subnet_group.this.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this[0].name
  vpc_security_group_ids          = [aws_security_group.database.id]
  backup_retention_period         = 7
  copy_tags_to_snapshot           = true
  deletion_protection             = true
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${var.name}-aurora-final"
  apply_immediately               = false
  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }
  tags = local.tags
  lifecycle { prevent_destroy = true }
}
resource "aws_rds_cluster_instance" "writer" {
  count                      = var.database_mode == "aurora-serverless" ? 1 : 0
  identifier                 = "${var.name}-writer"
  cluster_identifier         = aws_rds_cluster.this[0].id
  instance_class             = "db.serverless"
  engine                     = aws_rds_cluster.this[0].engine
  engine_version             = aws_rds_cluster.this[0].engine_version
  db_subnet_group_name       = aws_db_subnet_group.this.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true
  promotion_tier             = 0
  tags                       = local.tags
}
locals {
  database_address           = var.database_mode == "aurora-serverless" ? aws_rds_cluster.this[0].endpoint : aws_db_instance.this[0].address
  database_master_secret_arn = var.database_mode == "aurora-serverless" ? aws_rds_cluster.this[0].master_user_secret[0].secret_arn : aws_db_instance.this[0].master_user_secret[0].secret_arn
}
