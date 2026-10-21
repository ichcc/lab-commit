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

variable "db_engine_version" {
  type    = string
  default = "18"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_name" {
  type    = string
  default = "lab"
}

variable "db_username" {
  type    = string
  default = "lab_admin"
}

variable "backend_namespace" {
  type    = string
  default = "lab"
}

variable "backend_service_account" {
  type    = string
  default = "backend"
}
