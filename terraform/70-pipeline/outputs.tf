output "repository_urls" {
  value = { for name, repo in aws_ecr_repository.app : name => repo.repository_url }
}

output "github_secret_arn" {
  value = aws_secretsmanager_secret.github.arn
}

output "codebuild_project" {
  value = var.github_token_ready ? aws_codebuild_project.release[0].name : null
}

output "webhook_url" {
  value = var.github_token_ready ? aws_codebuild_webhook.release[0].payload_url : null
}
