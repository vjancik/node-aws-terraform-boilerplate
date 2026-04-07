output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}


output "karpenter_interruption_queue_name" {
  description = "SQS queue name for Karpenter spot interruption handling"
  value       = aws_sqs_queue.karpenter_interruption.name
}

output "node_role_name" {
  description = "IAM role name for EKS nodes (used in Karpenter EC2NodeClass)"
  value       = aws_iam_role.node.name
}

output "node_role_arn" {
  description = "IAM role ARN for EKS nodes"
  value       = aws_iam_role.node.arn
}

output "github_actions_eks_deploy_role_arn" {
  description = "IAM role ARN for GitHub Actions EKS deploy"
  value       = aws_iam_role.github_actions_eks_deploy.arn
}
