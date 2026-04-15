variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for bastion resources"
  type        = string
  default     = "node-tf"
}
