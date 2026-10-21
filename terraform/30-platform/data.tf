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
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
  oidc_arn     = data.terraform_remote_state.eks.outputs.oidc_provider_arn
  oidc_issuer  = data.terraform_remote_state.eks.outputs.oidc_issuer
  vpc_id       = data.terraform_remote_state.network.outputs.vpc_id
  ecr          = data.terraform_remote_state.eks.outputs.ecr_registry
}

data "aws_eks_cluster" "this" {
  name = local.cluster_name
}
