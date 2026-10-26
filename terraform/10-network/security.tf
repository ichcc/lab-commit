data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.region}.s3"
}

resource "aws_security_group" "endpoints" {
  name        = "${var.project}-endpoints"
  description = "Interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project}-endpoints"
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  security_group_id = aws_security_group.endpoints.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from VPC"
}

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb"
  description = "Internal ALB"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project}-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from VPC"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_redirect" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP redirect from VPC"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_vpc" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
  description       = "Targets inside VPC"
}

resource "aws_security_group" "admin_alb" {
  name        = "${var.project}-admin-alb"
  description = "Internet-facing ALB for Argo CD and Grafana"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project}-admin-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "admin_alb_https" {
  for_each = toset(var.admin_cidrs)

  security_group_id = aws_security_group.admin_alb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from admin"
}

resource "aws_vpc_security_group_ingress_rule" "admin_alb_http_redirect" {
  for_each = toset(var.admin_cidrs)

  security_group_id = aws_security_group.admin_alb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP redirect from admin"
}

resource "aws_vpc_security_group_egress_rule" "admin_alb_to_vpc" {
  security_group_id = aws_security_group.admin_alb.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
  description       = "Targets inside VPC"
}

resource "aws_security_group" "windows" {
  name        = "${var.project}-windows"
  description = "Windows test instance"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project}-windows"
  }
}

resource "aws_vpc_security_group_egress_rule" "windows_https_vpc" {
  security_group_id = aws_security_group.windows.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS to VPC"
}

resource "aws_vpc_security_group_egress_rule" "windows_https_s3" {
  security_group_id = aws_security_group.windows.id
  prefix_list_id    = data.aws_prefix_list.s3.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS to S3"
}

resource "aws_vpc_security_group_egress_rule" "windows_dns" {
  security_group_id = aws_security_group.windows.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  description       = "DNS to VPC resolver"
}

resource "aws_vpc_security_group_egress_rule" "windows_grafana" {
  security_group_id = aws_security_group.windows.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP to ALB"
}
