variable "region" {
  type = string
}

variable "project" {
  type    = string
  default = "lab-commit"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "interface_endpoints" {
  type = list(string)
  default = [
    "ecr.api",
    "ecr.dkr",
    "sts",
    "logs",
    "ec2",
    "elasticloadbalancing",
    "ssm",
    "ssmmessages",
    "ec2messages",
    "secretsmanager",
    "eks",
    "codebuild",
    "kms",
  ]
}
