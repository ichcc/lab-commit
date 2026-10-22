output "instance_id" {
  value = aws_instance.windows.id
}

output "private_ip" {
  value = aws_instance.windows.private_ip
}

output "installers_bucket" {
  value = aws_s3_bucket.installers.id
}

output "admin_password_parameter" {
  value = aws_ssm_parameter.admin_password.name
}

output "association_id" {
  value = aws_ssm_association.setup.association_id
}
