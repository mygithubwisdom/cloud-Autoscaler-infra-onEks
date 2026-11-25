resource "aws_ecr_repository" "api" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Retain the newest 30 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# PostgreSQL bootstrap container repository
resource "aws_ecr_repository" "bootstrap" {
  name                 = var.bootstrap_ecr_repository_name
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

# Retain the newest 30 bootstrap images
resource "aws_ecr_lifecycle_policy" "bootstrap" {
  repository = aws_ecr_repository.bootstrap.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Retain the newest 30 bootstrap images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
