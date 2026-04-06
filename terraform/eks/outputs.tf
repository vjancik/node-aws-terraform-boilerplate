output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "github_actions_eks_deploy_role_arn" {
  description = "IAM role ARN for GitHub Actions EKS deploy job"
  value       = module.eks.github_actions_eks_deploy_role_arn
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN — add this to the Ingress annotation after DNS validation"
  value       = aws_acm_certificate.main.arn
}

output "acm_certificate_validation_options" {
  description = "DNS records to create for ACM certificate validation"
  value = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
}
