output "certificate_arn" {
  value = aws_acm_certificate.this.arn
}

output "ca_certificate_pem" {
  value = tls_self_signed_cert.ca.cert_pem
}

output "ca_certificate_parameter" {
  value = aws_ssm_parameter.ca_certificate.name
}

output "zone_id" {
  value = aws_route53_zone.private.zone_id
}

output "zone_name" {
  value = aws_route53_zone.private.name
}

output "hostnames" {
  value = values(local.fqdns)
}

output "alb_dns_name" {
  value = var.alb_ready ? data.aws_lb.ingress[0].dns_name : null
}
