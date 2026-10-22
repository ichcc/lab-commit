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

variable "zone_name" {
  type    = string
  default = "lab.internal"
}

variable "hostnames" {
  type    = list(string)
  default = ["lab-commit-task", "argocd", "grafana"]
}

variable "alb_ready" {
  type    = bool
  default = false
}

variable "alb_group_name" {
  type    = string
  default = "lab-commit"
}

variable "certificate_validity_hours" {
  type    = number
  default = 8760
}
