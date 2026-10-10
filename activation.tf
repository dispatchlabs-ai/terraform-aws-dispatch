variable "enable_activation" {
  description = "Register an unscheduled one-shot private activation task. Invoke explicitly after launcher and backend startup, before waiting for readiness."
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_activation || (var.application != null && var.image != null)
    error_message = "Activation requires an image and typed application configuration."
  }
}
locals {
  activation_enabled = var.enable_activation && var.application != null && var.image != null
}
resource "aws_security_group" "activation" {
  count       = local.activation_enabled ? 1 : 0
  name_prefix = "${var.name}-activation-"
  description = "One-shot authenticated activation, no inbound access"
  vpc_id      = aws_vpc.this.id
  tags        = local.tags
}
resource "aws_vpc_security_group_egress_rule" "activation_backend" {
  count                        = local.activation_enabled ? 1 : 0
  security_group_id            = aws_security_group.activation[0].id
  referenced_security_group_id = aws_security_group.tasks["backend"].id
  ip_protocol                  = "tcp"
  from_port                    = 3001
  to_port                      = 3001
}
resource "aws_vpc_security_group_ingress_rule" "activation_backend" {
  count                        = local.activation_enabled ? 1 : 0
  security_group_id            = aws_security_group.tasks["backend"].id
  referenced_security_group_id = aws_security_group.activation[0].id
  ip_protocol                  = "tcp"
  from_port                    = 3001
  to_port                      = 3001
}
resource "aws_vpc_security_group_egress_rule" "activation_https" {
  count             = local.activation_enabled ? 1 : 0
  security_group_id = aws_security_group.activation[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
resource "aws_iam_role" "activation_execution" {
  count              = local.activation_enabled ? 1 : 0
  name_prefix        = "${var.name}-activation-exec-"
  assume_role_policy = local.task_trust
  tags               = local.tags
}
resource "aws_iam_role" "activation_task" {
  count              = local.activation_enabled ? 1 : 0
  name_prefix        = "${var.name}-activation-"
  assume_role_policy = local.task_trust
  tags               = local.tags
}
resource "aws_iam_role_policy" "activation_execution" {
  count = local.activation_enabled ? 1 : 0
  role  = aws_iam_role.activation_execution[0].id
  policy = jsonencode({ Version = "2012-10-17", Statement = concat([
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"], Resource = concat([aws_ecr_repository.this.arn], tolist(var.image_pull_repository_arns)) },
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.this["bootstrap"].arn}:*" },
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = var.application.token_secret_arns.operator }
    ], length(var.secret_kms_key_arns) == 0 ? [] : [{
      Effect    = "Allow", Action = ["kms:Decrypt"], Resource = tolist(var.secret_kms_key_arns),
      Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${data.aws_region.current.region}.amazonaws.com" } }
  }]) })
}
resource "aws_ecs_task_definition" "activation" {
  count                    = local.activation_enabled ? 1 : 0
  family                   = "${var.name}-activation"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.activation_execution[0].arn
  task_role_arn            = aws_iam_role.activation_task[0].arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }
  container_definitions = jsonencode([{
    name            = "activation", image = var.image, essential = true,
    user            = "65532:65532", readonlyRootFilesystem = true,
    linuxParameters = { initProcessEnabled = true, capabilities = { add = [], drop = ["ALL"] } },
    command         = ["node", "-e", file("${path.module}/templates/activate.cjs")],
    environment = [
      { name = "DISPATCH_BACKEND_ORIGIN", value = "https://backend.${aws_service_discovery_private_dns_namespace.this.name}:3001" },
      { name = "DISPATCH_BACKEND_CA", value = var.application.backend_ca_pem }
    ],
    secrets = [{ name = "DISPATCH_OPERATOR_TOKEN", valueFrom = var.application.token_secret_arns.operator }],
    logConfiguration = { logDriver = "awslogs", options = {
      awslogs-group  = aws_cloudwatch_log_group.this["bootstrap"].name,
      awslogs-region = data.aws_region.current.region, awslogs-stream-prefix = "activation"
    } }
  }])
  tags = local.tags
}
output "activation" {
  value = local.activation_enabled ? {
    task_definition_arn = aws_ecs_task_definition.activation[0].arn
    security_group_id   = aws_security_group.activation[0].id
  } : null
  description = "Unscheduled one-shot activation task. Use service_cluster_arn/private_subnet_ids. Never automatically retry an uncertain result."
}
