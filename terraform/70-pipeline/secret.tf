resource "aws_secretsmanager_secret" "github" {
  name                    = "${var.project}/github-token"
  description             = "GitHub token for CodeBuild source, webhook and chart commit-back"
  recovery_window_in_days = 0

  tags = {
    "codebuild:source"          = ""
    "codebuild:source:type"     = "personal_access_token"
    "codebuild:source:provider" = "github"
  }
}

resource "aws_codebuild_source_credential" "github" {
  count = var.github_token_ready ? 1 : 0

  auth_type   = "SECRETS_MANAGER"
  server_type = "GITHUB"
  token       = aws_secretsmanager_secret.github.arn
}
