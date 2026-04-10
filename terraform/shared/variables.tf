variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "root_domain" {
  description = "Root domain for the wildcard ACM certificate (e.g. yourdomain.com)"
  type        = string
}
