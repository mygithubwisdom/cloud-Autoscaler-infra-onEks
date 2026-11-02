variable "ecr_repository_name" {
  description = "Name of the private ECR repository."
  type        = string
  default     = "cloud-engineer-onEks-assessment/assessment-api"
}

variable "aws_region" {
  description = "AWS region for ECR and the GitHub Actions IAM role."
  type        = string
  default     = "us-east-1"
}


variable "project" {
  description = "Project name and mandatory project tag."
  type        = string
  default     = "cloud-engineer-onEks-assessment"
}


variable "environment" {
  description = "Environment represented by the shared image registry."
  type        = string
  default     = "shared"
}

variable "owner" {
  description = "Mandatory owner tag for accountability and cost allocation."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository in owner/name format."
  type        = string
  default     = "mygithubwisdom/cloud-Autoscaler-infra-onEks"
}

variable "github_branch" {
  description = "Only this branch may assume the GitHub Actions IAM role."
  type        = string
  default     = "main"
}

variable "existing_github_oidc_provider_arn" {
  description = "ARN of the existing AWS GitHub OIDC provider"
  type        = string
}
