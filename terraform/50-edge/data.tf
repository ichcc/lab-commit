data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "10-network/terraform.tfstate"
    region = var.region
  }
}

locals {
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id
  fqdns  = { for name in var.hostnames : name => "${name}.${var.zone_name}" }
}
