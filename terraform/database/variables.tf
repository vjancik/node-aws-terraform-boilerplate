variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for all database resources"
  type        = string
  default     = "node-tf-db"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "app"
}

variable "db_username" {
  description = "Master database username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Master database password"
  type        = string
  sensitive   = true
}
