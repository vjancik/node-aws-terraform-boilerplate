output "alb_dns_name" {
  description = "ALB DNS name — add this as a CNAME record in your domain DNS provider pointing to your domain_name"
  value       = module.ecs.alb_dns_name
}

output "acm_validation_records" {
  description = "DNS records to add in your domain DNS provider to validate the ACM certificate"
  value       = module.ecs.acm_validation_records
}

output "github_actions_ecs_deploy_role_arn" {
  description = "IAM role ARN for ECS deployments — add to GitHub repo secrets as AWS_ECS_ROLE_ARN"
  value       = aws_iam_role.github_actions_ecs_deploy.arn
}
