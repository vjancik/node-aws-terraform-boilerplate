output "ecr_backend_repository_url" {
  description = "ECR repository URL for the backend image"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_web_repository_url" {
  description = "ECR repository URL for the web image"
  value       = aws_ecr_repository.web.repository_url
}

output "github_actions_role_arn" {
  description = "IAM role ARN to use in the GHA workflow"
  value       = aws_iam_role.github_actions.arn
}

output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

output "acm_wildcard_certificate_arn" {
  description = "Wildcard ACM certificate ARN (*.root_domain) — shared across ECS and EKS ALBs"
  value       = aws_acm_certificate.wildcard.arn
}

output "acm_wildcard_certificate_validation_options" {
  description = "DNS records to add to Cloudflare to activate the wildcard cert"
  value = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
}

output "waf_acl_arn" {
  description = "Shared WAF WebACL ARN — attach to ECS and EKS ALBs"
  value       = aws_wafv2_web_acl.main.arn
}

output "secret_arn_web" {
  description = "Secrets Manager ARN for web container secrets"
  value       = aws_secretsmanager_secret.web.arn
}

output "secret_arn_backend" {
  description = "Secrets Manager ARN for backend container secrets"
  value       = aws_secretsmanager_secret.backend.arn
}
