# All ordinary launcher callers use this ingress before rolling is enabled.
# Peer handover remains direct and authenticated, not load balanced.
resource "aws_lb" "launcher" {
  access_logs {
    enabled = true
    bucket  = aws_s3_bucket.access_logs.id
    prefix  = "internal"
  }
  depends_on                 = [aws_s3_bucket_policy.access_logs, aws_s3_bucket_server_side_encryption_configuration.access_logs]
  count                      = var.launcher_internal_alb && !local.shared_private_alb ? 1 : 0
  name                       = "${var.name}-launcher"
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.tasks["launcher_alb"].id]
  subnets                    = aws_subnet.private[*].id
  idle_timeout               = var.idle_timeout_seconds
  drop_invalid_header_fields = true
  tags                       = local.tags
}
resource "aws_lb_target_group" "launcher" {
  count                = var.launcher_internal_alb ? 1 : 0
  name                 = "${var.name}-launcher"
  port                 = 8830
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.this.id
  deregistration_delay = var.deregistration_delay_seconds
  health_check {
    path     = "/internal/ready"
    protocol = "HTTP"
    matcher  = "200"
  }
  tags = local.tags
}
resource "aws_lb_listener" "launcher" {
  count             = var.launcher_internal_alb ? 1 : 0
  load_balancer_arn = local.control_alb_arn
  port              = 8830
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.launcher[0].arn
  }
}
