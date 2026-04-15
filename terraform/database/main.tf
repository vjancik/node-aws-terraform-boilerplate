terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "terraform_remote_state" "shared" {
  backend = "local"
  config = {
    path = "../shared/terraform.tfstate"
  }
}

locals {
  private_subnet_ids = data.terraform_remote_state.shared.outputs.private_subnet_ids
  vpc_id             = data.terraform_remote_state.shared.outputs.vpc_id
}

# ── Security group ─────────────────────────────────────────────────────────────

resource "aws_security_group" "rds" {
  name   = "${var.name}-rds-sg"
  vpc_id = local.vpc_id

  ingress {
    description = "Postgres from within VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── Subnet group ───────────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name       = "${var.name}-db-subnet-group"
  subnet_ids = local.private_subnet_ids
}

# ── RDS Postgres ───────────────────────────────────────────────────────────────
# t4g.micro: 2 vCPU, 1GB RAM, ~$9/month, 80 max connections.
# For multi-AZ (zero-downtime failover and instance class upgrades):
#   multi_az = true   # ~2x cost, adds a synchronous standby in a second AZ

resource "aws_db_instance" "main" {
  identifier        = var.name
  engine            = "postgres"
  engine_version    = "18"
  instance_class    = "db.t4g.micro"
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = false # set to true for zero-downtime failover and instance class upgrades
  publicly_accessible = false
  skip_final_snapshot = true # set to false in production and add final_snapshot_identifier = "${var.name}-final-snapshot" to retain a recovery point on destroy

  # NOTE: free tier accounts only support backup_retention_period = 0 (disabled).
  # Reasonable production default is 7. Upgrade account to re-enable.
  backup_retention_period = 0 # production default: 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"
}

# ── RDS Proxy ─────────────────────────────────────────────────────────────────
# Pools connections to RDS — prevents exhausting the 80-connection limit on t4g.micro
# when multiple ECS tasks or EKS pods scale up.
# Cost: $0.015 per vCPU/hour × 2 vCPU = ~$22/month.
#
# Apps connect to proxy_endpoint:5432 instead of the RDS endpoint directly.
# Use transaction pooling mode in your ORM/connection pool for best results.
#
# NOTE: RDS Proxy is not available on free tier accounts. Uncomment to enable
# after upgrading. Update DATABASE_URL in app secrets to point at the proxy
# endpoint instead of the RDS endpoint directly.

# resource "aws_iam_role" "rds_proxy" {
#   name = "${var.name}-rds-proxy"
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "rds.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
# }
#
# resource "aws_iam_role_policy" "rds_proxy" {
#   name = "rds-proxy-secrets"
#   role = aws_iam_role.rds_proxy.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect   = "Allow"
#       Action   = ["secretsmanager:GetSecretValue"]
#       Resource = aws_secretsmanager_secret.db_credentials.arn
#     }]
#   })
# }
#
# # RDS Proxy requires credentials via Secrets Manager (not direct username/password)
# resource "aws_secretsmanager_secret" "db_credentials" {
#   name = "${var.name}-db-credentials"
# }
#
# resource "aws_secretsmanager_secret_version" "db_credentials" {
#   secret_id = aws_secretsmanager_secret.db_credentials.id
#   secret_string = jsonencode({
#     username = var.db_username
#     password = var.db_password
#   })
# }
#
# resource "aws_db_proxy" "main" {
#   name                   = var.name
#   debug_logging          = false
#   engine_family          = "POSTGRESQL"
#   idle_client_timeout    = 1800
#   require_tls            = true
#   role_arn               = aws_iam_role.rds_proxy.arn
#   vpc_security_group_ids = [aws_security_group.rds.id]
#   vpc_subnet_ids         = local.private_subnet_ids
#
#   auth {
#     auth_scheme = "SECRETS"
#     iam_auth    = "DISABLED"
#     secret_arn  = aws_secretsmanager_secret.db_credentials.arn
#   }
# }
#
# resource "aws_db_proxy_default_target_group" "main" {
#   db_proxy_name = aws_db_proxy.main.name
#
#   connection_pool_config {
#     max_connections_percent      = 90 # proxy uses up to 90% of RDS max_connections (72 of 80)
#     max_idle_connections_percent = 50
#   }
# }
#
# resource "aws_db_proxy_target" "main" {
#   db_instance_identifier = aws_db_instance.main.identifier
#   db_proxy_name          = aws_db_proxy.main.name
#   target_group_name      = aws_db_proxy_default_target_group.main.name
# }
