variable "region" {
  type = string
}

variable "project" {
  type    = string
  default = "lab-commit"
}

variable "budget_usd" {
  type    = number
  default = 100
}

variable "budget_email" {
  type = string
}
