output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "windows_security_group_id" {
  value = aws_security_group.windows.id
}

output "endpoints_security_group_id" {
  value = aws_security_group.endpoints.id
}
