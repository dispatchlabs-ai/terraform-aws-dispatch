variable "task_egress" {
  description = "public-ip removes fixed NAT cost; each running task pays IPv4 egress cost. Ingress remains SG-restricted. nat retains private task placement with a permanent NAT gateway."
  type        = string
  default     = "public-ip"
  validation {
    condition     = contains(["public-ip", "nat"], var.task_egress)
    error_message = "Use public-ip or nat."
  }
}
locals {
  task_assign_public_ip = var.task_egress == "public-ip"
  task_subnet_ids       = local.task_assign_public_ip ? aws_subnet.public[*].id : aws_subnet.private[*].id
  shared_private_alb    = var.launcher_internal_alb && var.internal_alb && local.backend_alb_enabled
  control_alb_arn       = local.shared_private_alb ? aws_lb.this[0].arn : try(aws_lb.launcher[0].arn, null)
  control_alb_dns_name  = local.shared_private_alb ? aws_lb.this[0].dns_name : try(aws_lb.launcher[0].dns_name, null)
  control_alb_zone_id   = local.shared_private_alb ? aws_lb.this[0].zone_id : try(aws_lb.launcher[0].zone_id, null)
  callback_port         = local.shared_private_alb ? 8443 : 443
}
output "task_subnet_ids" { value = local.task_subnet_ids }
output "task_assign_public_ip" { value = local.task_assign_public_ip }
