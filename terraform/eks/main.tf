terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Auth providers configured after cluster is known
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

# ── Read shared state (VPC) ────────────────────────────────────────────────────

data "terraform_remote_state" "shared" {
  backend = "local"
  config = {
    path = "../shared/terraform.tfstate"
  }
}

# ── EKS cluster ────────────────────────────────────────────────────────────────

module "eks" {
  source = "../modules/eks"

  name               = var.name
  aws_region         = var.aws_region
  vpc_id             = data.terraform_remote_state.shared.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.shared.outputs.private_subnet_ids

  github_org  = var.github_org
  github_repo = var.github_repo
}

# ── Tag subnets for ALB controller autodiscovery ───────────────────────────────
# The ALB controller discovers subnets via these tags.

resource "aws_ec2_tag" "public_subnet_eks" {
  for_each    = toset(data.terraform_remote_state.shared.outputs.public_subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_ec2_tag" "public_subnet_cluster" {
  for_each    = toset(data.terraform_remote_state.shared.outputs.public_subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.name}"
  value       = "shared"
}

resource "aws_ec2_tag" "private_subnet_internal_elb" {
  for_each    = toset(data.terraform_remote_state.shared.outputs.private_subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

resource "aws_ec2_tag" "private_subnet_cluster" {
  for_each    = toset(data.terraform_remote_state.shared.outputs.private_subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.name}"
  value       = "shared"
}

# ── WAF ───────────────────────────────────────────────────────────────────────
# Cost: ~$7/month (WebACL $5 + 2 managed rule groups $1 each)
# Disable by removing the wafV2 block from lbconfig.yaml and destroying this resource.

resource "aws_wafv2_web_acl" "alb" {
  name  = "${var.name}-alb-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitPerIP"
    priority = 3
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 10000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-alb-waf"
    sampled_requests_enabled   = true
  }
}

# ── ACM certificate ────────────────────────────────────────────────────────────

resource "aws_acm_certificate" "main" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# ── metrics-server ─────────────────────────────────────────────────────────────
# Required for HPA to read pod CPU/memory metrics.

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.13.0"

  set = [
    {
      name  = "args[0]"
      value = "--kubelet-preferred-address-types=InternalIP"
    }
  ]

  depends_on = [module.eks]
}

# ── AWS Load Balancer Controller ───────────────────────────────────────────────

resource "kubernetes_service_account_v1" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
  }
  depends_on = [module.eks]
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.2.1"

  set = [
    { name = "clusterName",                                        value = module.eks.cluster_name },
    { name = "serviceAccount.create",                              value = "false" },
    { name = "serviceAccount.name",                                value = "aws-load-balancer-controller" },
    { name = "region",                                             value = var.aws_region },
    { name = "vpcId",                                              value = data.terraform_remote_state.shared.outputs.vpc_id },
    # Enable Gateway API support (required for Gateway/HTTPRoute resources)
    { name = "controllerConfig.featureGates.ALBGatewayAPI",        value = "true" },
  ]

  depends_on = [kubernetes_service_account_v1.alb_controller]
}

# ── Gateway API CRDs ───────────────────────────────────────────────────────────
# Standard channel v1.2.1 — includes GatewayClass, Gateway, HTTPRoute (all GA).
# Must be installed before any Gateway/HTTPRoute resources are applied.
# To upgrade: change the version in the URL and re-apply.

resource "null_resource" "gateway_api_crds" {
  triggers = {
    version = "v1.5.1-standard"
  }

  provisioner "local-exec" {
    command = "kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml"
    environment = {
      KUBECONFIG = ""
      AWS_DEFAULT_REGION = var.aws_region
    }
  }

  depends_on = [module.eks]
}

# ── ExternalDNS (Cloudflare provider) ─────────────────────────────────────────
# Watches Gateway HTTPRoutes and automatically creates/updates DNS records
# in Cloudflare. Requires a Cloudflare API token stored as a k8s secret.
#
# Create the secret once (not managed by Terraform to avoid storing token in state):
#   kubectl create secret generic cloudflare-api-token \
#     --from-literal=token=<CF_API_TOKEN> \
#     -n kube-system

resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.20.0"

  set = [
    { name = "provider.name",                                 value = "cloudflare" },
    { name = "env[0].name",                                   value = "CF_API_TOKEN" },
    { name = "env[0].valueFrom.secretKeyRef.name",            value = "cloudflare-api-token" },
    { name = "env[0].valueFrom.secretKeyRef.key",             value = "token" },
    { name = "sources[0]",                                    value = "gateway-httproute" },
    { name = "policy",                                        value = "upsert-only" },
    { name = "txtOwnerId",                                    value = var.name },
  ]

  depends_on = [module.eks]
}

# ── Karpenter ──────────────────────────────────────────────────────────────────

resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.10.0"

  set = [
    { name = "settings.clusterName",                 value = module.eks.cluster_name },
    { name = "settings.interruptionQueue",           value = module.eks.karpenter_interruption_queue_name },
    { name = "controller.resources.requests.cpu",    value = "100m" },
    { name = "controller.resources.requests.memory", value = "256Mi" },
    # Default is 2. Requires 2 non-karpenter nodes to launch 2nd controller replica. Otherwise the second pod stays permanently Pending.
    { name = "replicas",                             value = "1" },
  ]

  depends_on = [module.eks]
}

# ── Karpenter NodePool + EC2NodeClass ──────────────────────────────────────────
# Defines what Karpenter can launch: ARM Graviton spot + on-demand,
# cheapest small instance types, spread equally across AZs.

resource "kubernetes_manifest" "karpenter_ec2_node_class" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      amiSelectorTerms = [{ alias = "al2023@latest" }]
      role             = module.eks.node_role_name
      subnetSelectorTerms = [
        { tags = { "kubernetes.io/cluster/${var.name}" = "shared" } }
      ]
      securityGroupSelectorTerms = [
        { tags = { "aws:eks:cluster-name" = module.eks.cluster_name } }
      ]
    }
  }

  depends_on = [helm_release.karpenter]
}

resource "kubernetes_manifest" "karpenter_node_pool" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "default"
    }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          requirements = [
            # ARM (Graviton) + AMD64 — lets Karpenter pick cheapest spot across both
            { key = "kubernetes.io/arch", operator = "In", values = ["arm64", "amd64"] },
            # Mix spot + on-demand; Karpenter prefers spot when available
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot", "on-demand"] },
            # t and c family — Karpenter picks cheapest spot at launch time
            { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["c", "t"] },
            { key = "karpenter.k8s.aws/instance-size", operator = "In", values = ["small", "medium"] },
          ]
        }
      }
      limits = {
        cpu    = "8"
        memory = "8Gi"
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
      }
    }
  }

  depends_on = [kubernetes_manifest.karpenter_ec2_node_class]
}
