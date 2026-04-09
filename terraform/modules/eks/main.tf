data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ── CloudWatch log group (retention — EKS creates this automatically otherwise) ─

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = 30
}

# ── EKS Cluster ────────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # audit, controllerManager, scheduler disabled — together they exceed the 5GB/month CloudWatch free tier.
  # Re-enable temporarily for debugging if needed.
  enabled_cluster_log_types = ["api", "authenticator"]

  depends_on = [
    aws_cloudwatch_log_group.eks_cluster,
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_resource_controller,
  ]
}


# ── Managed Node Group (bootstrap nodes — Karpenter takes over for scale-out) ──

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.name}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  ami_type       = "AL2023_ARM_64_STANDARD" # Graviton (arm64)
  instance_types = var.node_instance_types
  capacity_type  = "ON_DEMAND"

  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  update_config {
    max_unavailable = 1
  }

  # Spread nodes evenly across AZs via subnet placement
  # EKS node groups automatically distribute across the provided subnets

  labels = {
    "node-group" = "default"
  }

  # Allow Karpenter to manage the node group scaling
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_ecr,
    aws_iam_role_policy_attachment.node_cni,
  ]
}

# ── EKS Add-ons ────────────────────────────────────────────────────────────────
# To check latest available versions for each addon (replace K8S_VERSION as needed):
# aws eks describe-addon-versions --kubernetes-version 1.35 \
#   --query 'addons[?contains(`["coredns","kube-proxy","vpc-cni","eks-pod-identity-agent"]`, addonName)].{name:addonName,latest:addonVersions[0].addonVersion}' \
#   --output table

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  addon_version               = "v1.13.2-eksbuild.4"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  addon_version               = "v1.35.3-eksbuild.2"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  addon_version               = "v1.21.1-eksbuild.7"
  resolve_conflicts_on_update = "OVERWRITE"

  pod_identity_association {
    role_arn        = aws_iam_role.vpc_cni.arn
    service_account = "aws-node"
  }
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = "v1.3.10-eksbuild.2"
  resolve_conflicts_on_update = "OVERWRITE"
}
