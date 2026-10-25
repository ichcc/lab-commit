resource "aws_secretsmanager_secret" "github" {
  name                    = "${var.project}/github-token"
  description             = "GitHub token for the chart commit-back"
  recovery_window_in_days = 0
}
