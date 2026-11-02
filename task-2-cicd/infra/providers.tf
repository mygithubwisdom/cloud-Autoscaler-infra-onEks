provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    project     = var.project
    environment = var.environment
    owner       = var.owner
    managed-by  = "terraform"
  }

  github_subject = "repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"
}