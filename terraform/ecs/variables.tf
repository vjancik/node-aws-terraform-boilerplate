variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for all ECS resources"
  type        = string
  default     = "node-tf-ecs"
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
  description = "Domain name for the ACM certificate and ALB (e.g. api.yourdomain.com)"
  type        = string
}

variable "backend_image" {
  description = "Override image URI. If null, preserves the currently deployed image. Set explicitly to deploy a specific image."
  type        = string
  default     = null
}
