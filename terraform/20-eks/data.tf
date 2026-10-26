data "aws_caller_identity" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "10-network/terraform.tfstate"
    region = var.region
  }
}

locals {
  cluster_name    = "${var.project}-eks"
  subnet_ids      = data.terraform_remote_state.network.outputs.private_subnet_ids
  alb_sg_id       = data.terraform_remote_state.network.outputs.alb_security_group_id
  admin_alb_sg_id = data.terraform_remote_state.network.outputs.admin_alb_security_group_id
  windows_sg_id   = data.terraform_remote_state.network.outputs.windows_security_group_id
}
