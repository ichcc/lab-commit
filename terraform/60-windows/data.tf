data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "10-network/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "edge" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "50-edge/terraform.tfstate"
    region = var.region
  }
}

data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "ami" {
  name = var.ami_parameter
}

locals {
  subnet_id     = data.terraform_remote_state.network.outputs.private_subnet_ids[0]
  windows_sg_id = data.terraform_remote_state.network.outputs.windows_security_group_id
  ca_parameter  = data.terraform_remote_state.edge.outputs.ca_certificate_parameter
  account_id    = data.aws_caller_identity.current.account_id
}
