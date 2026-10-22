variable "region" {
  type = string
}

variable "project" {
  type    = string
  default = "lab-commit"
}

variable "state_bucket" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ami_parameter" {
  type    = string
  default = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

variable "root_volume_size" {
  type    = number
  default = 50
}

variable "chrome_key" {
  type    = string
  default = "chrome/googlechromestandaloneenterprise64.msi"
}
