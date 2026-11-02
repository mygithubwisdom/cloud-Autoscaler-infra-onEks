output "ecr_repository_url" {
  description = "URL used to tag and push Docker images"
  value       = aws_ecr_repository.api.repository_url
}

output "github_actions_role_arn" {
  description = "IAM role for the GitHub Actions ECR publishing workflow"
  value       = aws_iam_role.github_actions.arn
}