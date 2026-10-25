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

variable "chart_versions" {
  type = map(string)
  default = {
    lbc        = "3.6.0"
    argocd     = "10.10.5"
    keda       = "2.21.0"
    prometheus = "29.37.0"
    grafana    = "14.0.1"
  }
}

variable "keda_image_tag" {
  type    = string
  default = "2.21.0"
}

variable "grafana_image_tag" {
  type    = string
  default = "13.2.4"
}

variable "api_tunnel_port" {
  type    = number
  default = 0
}
