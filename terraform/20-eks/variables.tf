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

variable "cluster_version" {
  type    = string
  default = "1.36"
}

variable "admin_cidrs" {
  type = list(string)
}

variable "public_endpoint" {
  type    = bool
  default = true
}

variable "fargate_namespaces" {
  type    = list(string)
  default = ["default", "kube-system", "argocd", "keda", "monitoring", "lab"]
}

variable "pod_ports" {
  type    = list(number)
  default = [80, 3000, 8000, 8080, 9090]
}

variable "pull_through_cache" {
  type = map(string)
  default = {
    "ecr-public" = "public.ecr.aws"
    "k8s"        = "registry.k8s.io"
    "quay"       = "quay.io"
  }
}
