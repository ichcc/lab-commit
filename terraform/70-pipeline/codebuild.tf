resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/codebuild/${var.project}"
  retention_in_days = 7
}

resource "aws_security_group" "codebuild" {
  name        = "${var.project}-codebuild"
  description = "CodeBuild in VPC"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${var.project}-codebuild"
  }
}

resource "aws_vpc_security_group_egress_rule" "codebuild_all" {
  security_group_id = aws_security_group.codebuild.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "GitHub through NAT, AWS APIs through endpoints"
}

resource "aws_codebuild_project" "release" {
  name          = "${var.project}-release"
  description   = "Build images, push to ECR, bump the chart appVersion"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  source {
    type      = "CODEPIPELINE"
    buildspec = "pipeline/buildspec.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type            = "LINUX_CONTAINER"
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = var.build_image
    privileged_mode = true

    environment_variable {
      name  = "REGISTRY"
      value = local.registry
    }

    environment_variable {
      name  = "REPOSITORY_URL"
      value = local.repository_url
    }

    environment_variable {
      name  = "BRANCH"
      value = var.branch
    }

    environment_variable {
      name  = "GITHUB_TOKEN"
      type  = "SECRETS_MANAGER"
      value = "${aws_secretsmanager_secret.github.arn}:Token"
    }
  }

  vpc_config {
    vpc_id             = local.vpc_id
    subnets            = local.private_subnet_ids
    security_group_ids = [aws_security_group.codebuild.id]
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild.name
    }
  }

  depends_on = [aws_iam_role_policy.codebuild]
}

moved {
  from = aws_codebuild_project.release[0]
  to   = aws_codebuild_project.release
}
