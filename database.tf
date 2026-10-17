locals {
  distributed_databases = var.distributed_postgres == null ? {} : { workers = var.distributed_postgres }
}

resource "aws_db_subnet_group" "distributed" {
  for_each   = local.distributed_databases
  name       = "${var.name}-workers"
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]
  tags       = local.tags
}

resource "aws_security_group" "distributed_database" {
  for_each    = local.distributed_databases
  name        = "${var.name}-workers-database"
  description = "Private PostgreSQL from this EKS cluster only; Kubernetes policies narrow Pod access."
  vpc_id      = aws_vpc.this.id
  tags        = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "distributed_database" {
  for_each                     = local.distributed_databases
  security_group_id            = aws_security_group.distributed_database[each.key].id
  referenced_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS nodes and their VPC-networked Pods."
}

resource "aws_db_parameter_group" "distributed" {
  for_each    = local.distributed_databases
  name_prefix = "${var.name}-workers-"
  family      = "postgres17"
  tags        = local.tags

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  # The initializer and backend's scoped worker-role provisioner both refuse
  # password DDL unless inherited session settings prevent credential logging.
  dynamic "parameter" {
    for_each = {
      log_parameter_max_length           = "0"
      log_parameter_max_length_on_error  = "0"
      log_statement                      = "none"
      log_min_duration_statement         = "-1"
      log_min_duration_sample            = "-1"
      log_min_error_statement            = "panic"
      log_error_verbosity                = "terse"
      password_encryption                = "scram-sha-256"
      "pg_stat_statements.track_utility" = "0"
    }
    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "immediate"
    }
  }
}

resource "aws_db_instance" "distributed" {
  for_each                    = local.distributed_databases
  identifier                  = "${var.name}-workers"
  engine                      = "postgres"
  engine_version              = each.value.engine_version
  instance_class              = each.value.instance_class
  allocated_storage           = each.value.allocated_storage
  max_allocated_storage       = each.value.max_allocated_storage
  storage_type                = "gp3"
  storage_encrypted           = true
  username                    = "dispatch_operator"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.distributed[each.key].name
  parameter_group_name        = aws_db_parameter_group.distributed[each.key].name
  vpc_security_group_ids      = [aws_security_group.distributed_database[each.key].id]
  publicly_accessible         = false
  multi_az                    = false
  backup_retention_period     = each.value.backup_retention_period
  copy_tags_to_snapshot       = true
  delete_automated_backups    = false
  deletion_protection         = true
  skip_final_snapshot         = false
  final_snapshot_identifier   = "${var.name}-workers-final"
  auto_minor_version_upgrade  = false
  apply_immediately           = false
  tags                        = local.tags

  # PostgreSQL's maintenance database is sufficient for the separate operator
  # initializer, which creates seven isolated application databases and roles.
  lifecycle {
    prevent_destroy = true
  }
}
