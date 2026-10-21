data "aws_iam_policy_document" "backend_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${var.backend_namespace}:${var.backend_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backend" {
  name               = "${var.project}-backend"
  assume_role_policy = data.aws_iam_policy_document.backend_assume.json
}

data "aws_iam_policy_document" "backend_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_db_instance.this.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "backend_secret" {
  name   = "db-secret-read"
  role   = aws_iam_role.backend.id
  policy = data.aws_iam_policy_document.backend_secret.json
}
