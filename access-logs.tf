# ALB access logs require SSE-S3 (not SSE-KMS) and a same-region bucket.
# https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html
variable "access_log_retention_days" {
  description = "Days before ALB access logs expire. URLs may contain sensitive query strings; restrict read access."
  type        = number
  default     = 7
  validation {
    condition     = var.access_log_retention_days >= 1 && var.access_log_retention_days <= 365 && floor(var.access_log_retention_days) == var.access_log_retention_days
    error_message = "Use an integer retention from 1 to 365 days."
  }
}
resource "aws_s3_bucket" "access_logs" {
  bucket_prefix = "${var.name}-access-"
  force_destroy = false
  tags          = local.tags
}
resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule { object_ownership = "BucketOwnerEnforced" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    id     = "short-retention"
    status = "Enabled"
    filter {}
    expiration { days = var.access_log_retention_days }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}
resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ALBDelivery"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = [for prefix in ["public", "internal"] : "${aws_s3_bucket.access_logs.arn}/${prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
        Condition = { ArnLike = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:elasticloadbalancing:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:loadbalancer/*" } }
      },
      {
        Sid       = "TLSOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.access_logs.arn, "${aws_s3_bucket.access_logs.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}
output "access_log_bucket" {
  description = "Private ALB log bucket; public/ and internal/ prefixes. Delivery still requires live verification."
  value       = aws_s3_bucket.access_logs.id
}
