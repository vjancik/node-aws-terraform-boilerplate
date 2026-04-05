variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for Fargate tasks"
  type        = list(string)
}

variable "domain_name" {
  description = "Domain name for the ACM certificate and ALB listener"
  type        = string
}

variable "backend_image" {
  description = "Override image URI. If null, preserves the currently deployed image. Set explicitly to deploy a specific image."
  type        = string
  default     = null
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 3000
}

variable "task_cpu" {
  description = "Fargate task CPU units (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB"
  type        = number
  default     = 512
}

variable "min_tasks" {
  description = "Minimum number of ECS tasks"
  type        = number
  default     = 1
}

variable "max_tasks" {
  description = "Maximum number of ECS tasks"
  type        = number
  default     = 4
}

variable "task_execution_role_arn" {
  description = "IAM role ARN for ECS task execution (pull image, write logs)"
  type        = string
}

variable "task_role_arn" {
  description = "IAM role ARN for the running task (AWS API access)"
  type        = string
}
