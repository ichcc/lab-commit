output "repository_urls" {
  value = { for name, repo in aws_ecr_repository.app : name => repo.repository_url }
}

output "github_secret_arn" {
  value = aws_secretsmanager_secret.github.arn
}

output "codebuild_project" {
  value = aws_codebuild_project.release.name
}

output "pipeline_name" {
  value = aws_codepipeline.release.name
}

output "connection_arn" {
  value = aws_codestarconnections_connection.github.arn
}

output "connection_status" {
  value = aws_codestarconnections_connection.github.connection_status
}
