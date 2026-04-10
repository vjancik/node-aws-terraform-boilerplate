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

