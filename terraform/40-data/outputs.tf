output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "db_secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "db_security_group_id" {
  value = aws_security_group.db.id
}

output "backend_role_arn" {
  value = aws_iam_role.backend.arn
}
