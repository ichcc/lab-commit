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
  count = var.github_token_ready ? 1 : 0

  name          = "${var.project}-release"
  description   = "Build images, push to ECR, bump the chart appVersion"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  source {
    type            = "GITHUB"
    location        = local.repository_url
    git_clone_depth = 0
    buildspec       = "pipeline/buildspec.yml"
  }

  source_version = var.branch

  artifacts {
    type = "NO_ARTIFACTS"
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

  depends_on = [aws_codebuild_source_credential.github, aws_iam_role_policy.codebuild]
}

resource "aws_codebuild_webhook" "release" {
  count = var.github_token_ready ? 1 : 0

  project_name = aws_codebuild_project.release[0].name
  build_type   = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH"
    }

    filter {
      type    = "HEAD_REF"
      pattern = "^refs/heads/${var.branch}$"
    }

    filter {
      type    = "FILE_PATH"
      pattern = "^(VERSION|apps/.*)$"
    }

    filter {
      type                    = "COMMIT_MESSAGE"
      pattern                 = "\\[skip ci\\]"
      exclude_matched_pattern = true
    }
  }
}
