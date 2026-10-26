# SSM permissions attach to the actual worker role in iam.tf. EKS AL2023
# must have amazon-ssm-agent running; verify after nodes join. No SSH port/key.
# NAT is the default connectivity path. These endpoints are optional extras.
resource "aws_security_group" "endpoints" {
  count       = var.enable_ssm_endpoints ? 1 : 0
  name_prefix = "${local.name_prefix}-ssm-endpoints-"
  description = "Private SSM endpoints accessed by EKS workers"
  vpc_id      = aws_vpc.main.id
}
resource "aws_vpc_security_group_ingress_rule" "nodes_to_endpoints" {
  count                        = var.enable_ssm_endpoints ? 1 : 0
  security_group_id            = aws_security_group.endpoints[0].id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Workers to private SSM endpoints"
}
resource "aws_vpc_endpoint" "ssm" {
  for_each            = var.enable_ssm_endpoints ? toset(["ssm", "ssmmessages"]) : toset([])
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true
}
resource "aws_cloudwatch_log_group" "ssm_sessions" {
  name              = "/aws/ssm/${local.name_prefix}/sessions"
  retention_in_days = 30
}
resource "aws_iam_role_policy" "ssm_session_logs" {
  role = aws_iam_role.eks_nodes.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
        Resource = "${aws_cloudwatch_log_group.ssm_sessions.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      }
    ]
  })
}
# Explicit custom document, not account-wide SSM preferences. Supply its name
# with aws ssm start-session --document-name OUTPUT to enable these settings.
resource "aws_ssm_document" "session_logging" {
  name            = "${local.name_prefix}-session-logging"
  document_type   = "Session"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Project worker-node sessions streamed to CloudWatch"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName           = ""
      s3KeyPrefix            = ""
      s3EncryptionEnabled    = false
      cloudWatchLogGroupName = aws_cloudwatch_log_group.ssm_sessions.name
      # false means do not require a customer KMS key. CloudWatch still encrypts at rest.
      cloudWatchEncryptionEnabled = false
      cloudWatchStreamingEnabled  = true
      idleSessionTimeout          = "20"
      maxSessionDuration          = "60"
      runAsEnabled                = false
    }
  })
}
# Optional managed policy for an administrator to attach to an existing identity.
# Nothing is attached to a human or existing GitHub role automatically.
resource "aws_iam_policy" "ssm_operator" {
  name = "${local.name_prefix}-ssm-operator"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = ["ssm:StartSession"]
        Resource  = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/*"
        Condition = { StringEquals = { "ssm:resourceTag/Project" = var.project_name, "ssm:resourceTag/Environment" = var.environment } }
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:StartSession", "ssm:GetDocument"]
        Resource = aws_ssm_document.session_logging.arn
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:TerminateSession", "ssm:ResumeSession"]
        Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:session/$${aws:userid}-*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ssm:DescribeInstanceInformation", "ssm:DescribeSessions", "ssm:GetConnectionStatus"]
        Resource = "*"
      }
    ]
  })
}
