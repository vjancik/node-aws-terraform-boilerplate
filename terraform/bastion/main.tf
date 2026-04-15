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

data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  ecr_registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
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

# ── ECS Cluster ────────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "bastion" {
  name = "${var.name}-bastion"
}

# ── Security group ─────────────────────────────────────────────────────────────

resource "aws_security_group" "bastion" {
  name   = "${var.name}-bastion-sg"
  vpc_id = local.vpc_id

  # No ingress — ECS Exec tunnels through SSM, no inbound ports needed
  egress {
    description = "HTTPS for SSM tunnel and AWS API calls"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Postgres to RDS proxy"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
}

# ── IAM ────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "bastion_task_execution" {
  name = "${var.name}-bastion-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_task_execution" {
  role       = aws_iam_role.bastion_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "bastion_task" {
  name = "${var.name}-bastion-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Required for ECS Exec / SSM tunnel
resource "aws_iam_role_policy" "bastion_ssm" {
  name = "ssm-exec"
  role = aws_iam_role.bastion_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })
}

# ── S3 admin bucket ────────────────────────────────────────────────────────────
# Stores versioned admin scripts (e.g. setup-db.sql) for use inside bastion sessions.
# Cost: effectively free — a few SQL files, occasional downloads.

resource "aws_s3_bucket" "admin" {
  bucket = "${var.name}-admin"
}

resource "aws_s3_bucket_public_access_block" "admin" {
  bucket = aws_s3_bucket.admin.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "admin" {
  bucket = aws_s3_bucket.admin.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "setup_db" {
  bucket = aws_s3_bucket.admin.id
  key    = "setup-db.sql"
  source = "${path.module}/../../scripts/admin/setup-db.sql"
  etag   = filemd5("${path.module}/../../scripts/admin/setup-db.sql")
}

# ── Migrator IAM ──────────────────────────────────────────────────────────────

resource "aws_iam_role" "migrator_task_execution" {
  name = "${var.name}-db-migrator-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "migrator_task_execution" {
  role       = aws_iam_role.migrator_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "migrator_task" {
  name = "${var.name}-db-migrator-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# ── CloudWatch log group ───────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "bastion" {
  name              = "/ecs/${var.name}/bastion"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "migrator" {
  name              = "/ecs/${var.name}/db-migrator"
  retention_in_days = 30
}

# ── Task definition ────────────────────────────────────────────────────────────
# postgres:17-alpine — compatible with Postgres 18 server (psql is backwards compatible).
# The container sleeps for 1 hour max as a safety net; it exits when you close the ECS Exec session
# or when the sleep expires — whichever comes first.
# Run via: scripts/admin/connect-db.sh

resource "aws_ecs_task_definition" "bastion" {
  family                   = "${var.name}-bastion"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.bastion_task_execution.arn
  task_role_arn            = aws_iam_role.bastion_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name      = "psql"
    image     = "postgres:18-alpine"
    essential = true
    # sleep infinity keeps the container alive until the task is explicitly stopped.
    # DATABASE_URL and the psql command are passed at runtime via ECS Exec in connect-db.sh.
    command   = ["sleep", "infinity"]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.bastion.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "bastion"
      }
    }
  }])
}

# ── Migrator task definition ───────────────────────────────────────────────────
# Runs drizzle-kit migrate as a one-off task. DATABASE_URL is injected at
# runtime via container overrides in migrate-db.sh — never baked into the image.
# Triggered by: scripts/admin/migrate-db.sh or the db workflow in CI.

resource "aws_ecs_task_definition" "db_migrator" {
  family                   = "${var.name}-db-migrator"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.migrator_task_execution.arn
  task_role_arn            = aws_iam_role.migrator_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name      = "migrator"
    image     = "${local.ecr_registry}/db-migrator:latest"
    essential = true

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.migrator.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "db-migrator"
      }
    }
  }])
}
