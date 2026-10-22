resource "aws_route53_zone" "private" {
  name          = var.zone_name
  force_destroy = true

  vpc {
    vpc_id = local.vpc_id
  }
}

data "aws_lb" "ingress" {
  count = var.alb_ready ? 1 : 0

  tags = {
    "ingress.k8s.aws/stack" = var.alb_group_name
  }
}

resource "aws_route53_record" "alb" {
  for_each = var.alb_ready ? local.fqdns : {}

  zone_id = aws_route53_zone.private.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = data.aws_lb.ingress[0].dns_name
    zone_id                = data.aws_lb.ingress[0].zone_id
    evaluate_target_health = false
  }
}
