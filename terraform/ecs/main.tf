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

module "ecs" {
  source = "../modules/ecs"

  name               = var.name
  aws_region         = var.aws_region
  vpc_id             = data.terraform_remote_state.shared.outputs.vpc_id
  public_subnet_ids  = data.terraform_remote_state.shared.outputs.public_subnet_ids
  private_subnet_ids = data.terraform_remote_state.shared.outputs.private_subnet_ids

  domain_name   = var.domain_name
  backend_image = var.backend_image

  task_execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn
}
