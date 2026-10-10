variable "domain" {
  description = "Managed HTTPS hostname and existing public Route53 hosted zone. Null supports custom caller-owned certificates without CloudFront."
  type        = object({ name = string, zone_id = string })
  default     = null
  validation {
    condition     = var.domain == null ? true : can(regex("^[a-z0-9][a-z0-9.-]+[a-z0-9]$", var.domain.name)) && !strcontains(var.domain.name, "..") && length(var.domain.zone_id) > 0
    error_message = "Supply a lowercase DNS hostname (not URL/wildcard) and existing public hosted zone ID."
  }
}
locals {
  managed_domain           = var.domain != null
  backend_alb_enabled      = var.domain != null || var.certificate_arn != null
  backend_certificate_arn  = local.managed_domain ? aws_acm_certificate_validation.regional[0].certificate_arn : var.certificate_arn
  callback_certificate_arn = local.managed_domain ? aws_acm_certificate_validation.regional[0].certificate_arn : var.backend_callback_certificate_arn
}
resource "aws_acm_certificate" "regional" {
  count                     = local.managed_domain ? 1 : 0
  domain_name               = var.domain.name
  subject_alternative_names = ["origin.${var.domain.name}", "callbacks.${var.domain.name}"]
  validation_method         = "DNS"
  lifecycle { create_before_destroy = true }
  tags = local.tags
}
resource "aws_acm_certificate" "edge" {
  provider          = aws.edge
  count             = local.managed_domain ? 1 : 0
  domain_name       = var.domain.name
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
  tags = local.tags
}
# ACM uses the same validation token across regions for the same hostname.
resource "aws_route53_record" "validation" {
  for_each = local.managed_domain ? { for v in aws_acm_certificate.regional[0].domain_validation_options : v.domain_name => v } : {}
  zone_id  = var.domain.zone_id
  name     = each.value.resource_record_name
  type     = each.value.resource_record_type
  records  = [each.value.resource_record_value]
  ttl      = 60
}
resource "aws_acm_certificate_validation" "regional" {
  count                   = local.managed_domain ? 1 : 0
  certificate_arn         = aws_acm_certificate.regional[0].arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}
resource "aws_acm_certificate_validation" "edge" {
  provider                = aws.edge
  count                   = local.managed_domain ? 1 : 0
  certificate_arn         = aws_acm_certificate.edge[0].arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}
resource "aws_route53_zone" "private" {
  count = local.managed_domain ? 1 : 0
  name  = "callbacks.${var.domain.name}"
  vpc { vpc_id = aws_vpc.this.id }
  tags = local.tags
}
resource "aws_route53_record" "callback" {
  count   = local.managed_domain ? 1 : 0
  zone_id = aws_route53_zone.private[0].zone_id
  name    = "callbacks.${var.domain.name}"
  type    = "A"
  alias {
    name                   = aws_lb.launcher[0].dns_name
    zone_id                = aws_lb.launcher[0].zone_id
    evaluate_target_health = false
  }
}
resource "aws_route53_record" "origin" {
  count   = local.managed_domain ? 1 : 0
  zone_id = var.domain.zone_id
  name    = "origin.${var.domain.name}"
  type    = "A"
  alias {
    name                   = aws_lb.this[0].dns_name
    zone_id                = aws_lb.this[0].zone_id
    evaluate_target_health = false
  }
}
