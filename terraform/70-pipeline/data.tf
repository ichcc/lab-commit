data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "10-network/terraform.tfstate"
    region = var.region
  }
}

data "aws_caller_identity" "current" {}

locals {
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  account_id         = data.aws_caller_identity.current.account_id
  registry           = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  repository_url     = "https://github.com/${var.github_owner}/${var.github_repo}.git"
}
