resource "aws_db_subnet_group" "app" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.Privatesubnet.id, aws_subnet.Privatesubnet_b.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
  }
}

resource "aws_security_group" "db_sg" {
  name        = "${var.project_name}-db-sg"
  description = "Security group for RDS database"
  vpc_id      = aws_vpc.main-webapp.id

  # Allow DB access from app servers only or private subnets 
  ingress {
    description     = "DB access from app servers"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app_server.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main-webapp.cidr_block]
  }

  tags = {
    Name        = "${var.project_name}-db-sg"
    Environment = var.environment
  }
}

# Use AWS default PostgreSQL version for this region (avoids "Cannot find version" errors)
data "aws_rds_engine_version" "postgres" {
  engine       = var.db_engine
  default_only = true
}

resource "aws_db_instance" "db" {
  identifier              = "${var.project_name}-db"
  allocated_storage       = var.db_allocated_storage
  engine                  = var.db_engine
  engine_version          = data.aws_rds_engine_version.postgres.version
  instance_class          = var.db_instance_class
  db_subnet_group_name    = aws_db_subnet_group.app.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  port                    = var.db_port
  multi_az                = var.db_multi_az
  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true
  publicly_accessible     = false

  # ... other settings
  storage_encrypted       = true
  kms_key_id              = var.rds_kms_key_arn # Use a Customer Managed Key for Production

  tags = {
    Name        = "${var.project_name}-db"
    Environment = var.environment
  }
}

resource "aws_security_group" "db_sg" {
  name        = "${var.project_name}-db-sg"
  description = "Security group for RDS database"
  vpc_id      = aws_vpc.main-webapp.id


  # Allow DB access from app servers only
  ingress {
    description     = "DB access from app servers"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app_server.id]
  }


  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main-webapp.cidr_block]
  }


  tags = {
    Name        = "${var.project_name}-db-sg"
    Environment = var.environment
  }
}




