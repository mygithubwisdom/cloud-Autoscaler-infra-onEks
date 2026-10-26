# AWS Systems Manager (SSM) Session Manager Configuration

# IAM Role for EC2 to use SSM
resource "aws_iam_role" "app_server_role" {
  name = "${var.project_name}-app-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-app-server-role"
  }
}

# Attach AWS managed SSM policy
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.app_server_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Custom policy for CloudWatch Logs
resource "aws_iam_role_policy" "ssm_cloudwatch" {
  name = "${var.project_name}-ssm-cloudwatch-policy"
  role = aws_iam_role.app_server_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::aws-ssm-*/*"
      }
    ]
  })
}

# IAM Instance Profile for EC2
resource "aws_iam_instance_profile" "app_server_profile" {
  name = "${var.project_name}-app-server-profile"
  role = aws_iam_role.app_server_role.name

  tags = {
    Name = "${var.project_name}-app-server-profile"
  }
}

# ============================================================================
# VPC Endpoints for SSM (Required for Private Subnet Access)

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main-webapp.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-vpc-endpoints-sg"
  }
}

# SSM Endpoint
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main-webapp.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ssm-endpoint"
  }
}

# SSM Messages Endpoint
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main-webapp.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ssmmessages-endpoint"
  }
}

# EC2 Messages Endpoint
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main-webapp.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ec2messages-endpoint"
  }
}

# ============================================================================
# CloudWatch Log Group for SSM Session Logs

resource "aws_cloudwatch_log_group" "ssm_sessions" {
  name              = "/aws/ssm/${var.project_name}/sessions"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-ssm-sessions"
  }
}

# ============================================================================
# SSM Document for Session Logging


resource "aws_ssm_document" "session_logging" {
  name            = "${var.project_name}-session-logging"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Document to hold regional settings for Session Manager"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = ""
      s3KeyPrefix                 = ""
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.ssm_sessions.name
      cloudWatchEncryptionEnabled = true
      cloudWatchStreamingEnabled  = true
      idleSessionTimeout          = "20"
      maxSessionDuration          = "60"
      runAsEnabled                = false
      runAsDefaultUser            = ""
    }
  })

  tags = {
    Name = "${var.project_name}-session-logging"
  }
}

#iam policy for s3 access for terraform backend
resource "aws_iam_policy" "s3_access" {
  name = "AllowS3TerraformBackendAccess"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::my-goapi-cloudeks-bucket-wisdom",
          "arn:aws:s3:::my-goapi-cloudeks-bucket-wisdom/*"
        ]
      },
      {
        Sid    = "EC2DescribeAccess"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}