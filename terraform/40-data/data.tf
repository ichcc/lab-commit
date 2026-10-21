data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "10-network/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "20-eks/terraform.tfstate"
    region = var.region
  }
}

locals {
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  cluster_sg_id      = data.terraform_remote_state.eks.outputs.cluster_security_group_id
  oidc_arn           = data.terraform_remote_state.eks.outputs.oidc_provider_arn
  oidc_issuer        = data.terraform_remote_state.eks.outputs.oidc_issuer
}
