data "aws_iam_policy_document" "fargate_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:fargateprofile/${local.cluster_name}/*"]
    }
  }
}

resource "aws_iam_role" "fargate" {
  name               = "${local.cluster_name}-fargate"
  assume_role_policy = data.aws_iam_policy_document.fargate_assume.json
}

resource "aws_iam_role_policy_attachment" "fargate" {
  role       = aws_iam_role.fargate.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

data "aws_iam_policy_document" "pull_through" {
  statement {
    actions = [
      "ecr:CreateRepository",
      "ecr:BatchImportUpstreamImage",
      "ecr:TagResource",
    ]
    resources = ["arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/*"]
  }
}

resource "aws_iam_role_policy" "pull_through" {
  name   = "pull-through-cache"
  role   = aws_iam_role.fargate.id
  policy = data.aws_iam_policy_document.pull_through.json
}

resource "aws_eks_fargate_profile" "ns" {
  for_each = toset(var.fargate_namespaces)

  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = each.value
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = local.subnet_ids

  selector {
    namespace = each.value
  }

  depends_on = [aws_iam_role_policy_attachment.fargate]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    computeType = "Fargate"
  })

  depends_on = [aws_eks_fargate_profile.ns]
}
