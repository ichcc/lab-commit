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

variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "branch" {
  type    = string
  default = "main"
}

variable "app_repositories" {
  type    = list(string)
  default = ["lab/backend", "lab/frontend"]
}

variable "build_image" {
  type    = string
  default = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
}

variable "github_token_ready" {
  type    = bool
  default = false
}
