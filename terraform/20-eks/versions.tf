terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project    = var.project
      ManagedBy  = "terraform"
      Owner      = "candidate02"
      Repository = "github.com/ichcc/lab-commit"
      Stack      = "20-eks"
    }
  }
}
