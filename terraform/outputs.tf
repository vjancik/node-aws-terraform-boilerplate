output "ecr_repository_url" {
  description = "ECR repository URL for the backend image"
  value       = aws_ecr_repository.backend.repository_url
}

output "github_actions_role_arn" {
  description = "IAM role ARN to use in the GHA workflow"
  value       = aws_iam_role.github_actions.arn
}
