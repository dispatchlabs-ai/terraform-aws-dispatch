data "aws_region" "edge" { provider = aws.edge }

variable "frontend_release_prefix" {
  description = "Immutable published SPA bundle prefix. Upload verified release before selecting it; Terraform never builds/uploads files."
  type        = string
  default     = "releases/initial"
  validation {
    condition     = can(regex("^releases/[A-Za-z0-9][A-Za-z0-9._-]*$", var.frontend_release_prefix)) && !strcontains(var.frontend_release_prefix, "..")
    error_message = "Use releases/<immutable-release-id> without traversal or a trailing slash."
  }
}
resource "aws_s3_bucket" "frontend" {
  count         = local.managed_domain ? 1 : 0
  bucket_prefix = "${var.name}-frontend-"
  tags          = local.tags
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_public_access_block" "frontend" {
  count                   = local.managed_domain ? 1 : 0
  bucket                  = aws_s3_bucket.frontend[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  count  = local.managed_domain ? 1 : 0
  bucket = aws_s3_bucket.frontend[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_cloudfront_origin_access_control" "frontend" {
  count                             = local.managed_domain ? 1 : 0
  name                              = "${var.name}-frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
# Rewrite only SPA navigation. Missing assets retain their real HTTP errors.
resource "aws_cloudfront_function" "spa" {
  count   = local.managed_domain ? 1 : 0
  name    = "${var.name}-spa"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-JS
  function handler(event) {
    var request = event.request;
    if (request.uri === '/internal' || request.uri.indexOf('/internal/') === 0) {
      return { statusCode: 404, statusDescription: 'Not Found' };
    }
    if (request.uri === '/' || request.uri.endsWith('/') || !request.uri.split('/').pop().includes('.')) {
      request.uri = '/index.html';
    }
    return request;
  }
  JS
}
resource "aws_cloudfront_vpc_origin" "backend" {
  count = local.managed_domain ? 1 : 0
  vpc_origin_endpoint_config {
    name                   = "${var.name}-backend"
    arn                    = aws_lb.this[0].arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "https-only"
    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
  depends_on = [aws_internet_gateway.this, aws_lb_listener.https, aws_vpc_security_group_ingress_rule.cloudfront]
  tags       = local.tags
}
data "aws_ec2_managed_prefix_list" "cloudfront" {
  count = local.managed_domain ? 1 : 0
  name  = "com.amazonaws.global.cloudfront.origin-facing"
}
resource "aws_vpc_security_group_ingress_rule" "cloudfront" {
  count             = local.managed_domain ? 1 : 0
  security_group_id = aws_security_group.tasks["alb"].id
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront[0].id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
resource "aws_cloudfront_cache_policy" "static" {
  count       = local.managed_domain ? 1 : 0
  name        = "${var.name}-static"
  min_ttl     = 0
  default_ttl = 60
  max_ttl     = 31536000
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
  }
}
resource "aws_cloudfront_cache_policy" "api" {
  count       = local.managed_domain ? 1 : 0
  name        = "${var.name}-api-no-cache"
  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 0
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = false
    enable_accept_encoding_gzip   = false
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
  }
}
resource "aws_cloudfront_origin_request_policy" "api" {
  count = local.managed_domain ? 1 : 0
  name  = "${var.name}-api"
  cookies_config { cookie_behavior = "all" }
  headers_config { header_behavior = "allViewer" }
  query_strings_config { query_string_behavior = "all" }
}
resource "aws_cloudfront_distribution" "frontend" {
  count               = local.managed_domain ? 1 : 0
  enabled             = true
  is_ipv6_enabled     = true
  aliases             = [var.domain.name]
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  http_version        = "http2and3"
  origin {
    origin_id                = "spa"
    domain_name              = aws_s3_bucket.frontend[0].bucket_regional_domain_name
    origin_path              = "/${var.frontend_release_prefix}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend[0].id
  }
  origin {
    origin_id   = "api"
    domain_name = "origin.${var.domain.name}"
    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.backend[0].id
      origin_keepalive_timeout = 5
      origin_read_timeout      = 60
    }
  }
  default_cache_behavior {
    target_origin_id       = "spa"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = aws_cloudfront_cache_policy.static[0].id
    compress               = true
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa[0].arn
    }
  }
  dynamic "ordered_cache_behavior" {
    for_each = ["/api", "/api/*"]
    content {
      path_pattern             = ordered_cache_behavior.value
      target_origin_id         = "api"
      viewer_protocol_policy   = "https-only"
      allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods           = ["GET", "HEAD"]
      cache_policy_id          = aws_cloudfront_cache_policy.api[0].id
      origin_request_policy_id = aws_cloudfront_origin_request_policy.api[0].id
      compress                 = false
    }
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.edge[0].certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
  lifecycle {
    precondition {
      condition     = var.internal_alb && var.launcher_internal_alb
      error_message = "Managed CloudFront requires private backend and launcher ALBs."
    }
    precondition {
      condition     = var.application == null ? true : var.application.origin == "https://${var.domain.name}" && var.application.callback_ca_pem != null
      error_message = "Managed domain requires matching application HTTPS origin and explicit public ACM callback CA trust."
    }
  }
  tags = local.tags
}
resource "aws_s3_bucket_policy" "frontend" {
  count  = local.managed_domain ? 1 : 0
  bucket = aws_s3_bucket.frontend[0].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Principal = { Service = "cloudfront.amazonaws.com" }, Action = "s3:GetObject", Resource = "${aws_s3_bucket.frontend[0].arn}/releases/*", Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.frontend[0].arn } } },
    { Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.frontend[0].arn, "${aws_s3_bucket.frontend[0].arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } }
  ] })
}
resource "aws_route53_record" "frontend" {
  for_each = local.managed_domain ? toset(["A", "AAAA"]) : toset([])
  zone_id  = var.domain.zone_id
  name     = var.domain.name
  type     = each.value
  alias {
    name                   = aws_cloudfront_distribution.frontend[0].domain_name
    zone_id                = aws_cloudfront_distribution.frontend[0].hosted_zone_id
    evaluate_target_health = false
  }
}
output "frontend_bucket" { value = try(aws_s3_bucket.frontend[0].id, null) }
output "frontend_distribution_id" { value = try(aws_cloudfront_distribution.frontend[0].id, null) }
output "frontend_release_prefix" { value = local.managed_domain ? var.frontend_release_prefix : null }
