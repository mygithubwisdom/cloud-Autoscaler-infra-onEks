resource "aws_db_subnet_group" "app" {
  name       = "${local.name_prefix}-db"
  subnet_ids = local.database_subnet_ids
}
resource "aws_db_parameter_group" "postgres" {
  name_prefix = "${local.name_prefix}-postgres-"
  family      = "postgres${split(".", var.db_engine_version)[0]}"
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  lifecycle { create_before_destroy = true }
}
resource "random_id" "db_snapshot" { byte_length = 4 }
resource "aws_db_instance" "db" {
  identifier                      = "${local.name_prefix}-db"
  engine                          = "postgres"
  engine_version                  = var.db_engine_version
  instance_class                  = var.db_instance_class
  allocated_storage               = 20
  max_allocated_storage           = 50
  storage_type                    = "gp3"
  storage_encrypted               = true
  db_subnet_group_name            = aws_db_subnet_group.app.name
  vpc_security_group_ids          = [aws_security_group.rds.id]
  parameter_group_name            = aws_db_parameter_group.postgres.name
  db_name                         = var.db_name
  username                        = "dbadmin"
  manage_master_user_password     = true
  port                            = 5432
  multi_az                        = var.db_multi_az
  backup_retention_period         = 7
  backup_window                   = "03:00-04:00"
  maintenance_window              = "sun:04:30-sun:05:30"
  copy_tags_to_snapshot           = true
  deletion_protection             = var.db_deletion_protection
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${local.name_prefix}-final-${random_id.db_snapshot.hex}"
  publicly_accessible             = false
  auto_minor_version_upgrade      = false
  apply_immediately               = false
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
}
# No secret value is stored by Terraform. A controlled Task 4 DB bootstrap Job
# creates a limited SQL app user and populates this secret with matching fields.
resource "aws_secretsmanager_secret" "app_db" {
  name_prefix             = "${local.name_prefix}/postgres-application-"
  description             = "Limited application DB credentials; populated by controlled DB bootstrap"
  recovery_window_in_days = 7
}
resource "aws_iam_role_policy" "app_secret" {
  role = aws_iam_role.workload["app"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = aws_secretsmanager_secret.app_db.arn
    }]
  })
}
# Distinct privileged migration/bootstrap service account; never use for API pods.
resource "aws_iam_role_policy" "migration_secrets" {
  role = aws_iam_role.workload["migration"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = aws_db_instance.db.master_user_secret[0].secret_arn
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret", "secretsmanager:PutSecretValue"]
        Resource = aws_secretsmanager_secret.app_db.arn
      }
    ]
  })
}
