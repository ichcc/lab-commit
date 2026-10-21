resource "helm_release" "lbc" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_versions["lbc"]
  timeout    = 900

  values = [yamlencode({
    clusterName   = local.cluster_name
    region        = var.region
    vpcId         = local.vpc_id
    replicaCount  = 1
    enableShield  = false
    enableWaf     = false
    enableWafv2   = false
    image         = { repository = "${local.ecr}/ecr-public/eks/aws-load-balancer-controller" }
    serviceAccount = {
      create      = true
      name        = "aws-load-balancer-controller"
      annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.lbc.arn }
    }
    resources = {
      requests = { cpu = "250m", memory = "512Mi" }
    }
  })]

  depends_on = [aws_iam_role_policy_attachment.lbc]
}
