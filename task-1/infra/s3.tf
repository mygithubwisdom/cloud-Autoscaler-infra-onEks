# Current AWS account ID for the ALB log-delivery bucket policy
data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "main" {}

# KMS key retained for any other project use; ALB logs use SSE-S3 below.
resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project_name}-s3-kms-key"
    Environment = var.environment
  }
}

# KMS Key Alias for S3
resource "aws_kms_alias" "s3" {
  name          = "alias/${var.project_name}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

# S3 Bucket for access logs
resource "aws_s3_bucket" "access_logs" {
  bucket = "my-alb-bucket-eks-236-access-logs-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-access-logs-bucket"
    Environment = var.environment
  }
}

# Block public access for access logs bucket
resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Keep bucket ownership with this account while allowing ELB log delivery.
resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Permit the Elastic Load Balancing log-delivery service to write access logs.
resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSLogDeliveryWrite"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.access_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Sid       = "AWSLogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.access_logs.arn
      },
      {
        Sid       = "AllowELBAccount"
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.main.arn }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.access_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.access_logs,
    aws_s3_bucket_ownership_controls.access_logs
  ]
}


# Random suffix for unique bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Server-side encryption for access logs bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

