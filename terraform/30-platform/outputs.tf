output "lbc_role_arn" {
  value = aws_iam_role.lbc.arn
}

output "grafana_admin_password" {
  value     = random_password.grafana.result
  sensitive = true
}
