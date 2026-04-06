variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for all EKS resources"
  type        = string
  default     = "node-tf-eks"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the ALB Ingress ACM certificate (e.g. api.yourdomain.com)"
  type        = string
}
