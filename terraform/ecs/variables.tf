variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Domain name for the ACM certificate and ALB (e.g. api.yourdomain.com)"
  type        = string
}

variable "backend_image" {
  description = "Full ECR image URI for the backend (e.g. 123456.dkr.ecr.us-east-1.amazonaws.com/backend:sha-abc)"
  type        = string
}
